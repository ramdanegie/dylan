import Foundation
import Testing
@testable import DylanCore

private let t0 = Date(timeIntervalSince1970: 1_762_160_400)   // sample timestamp from design D11

@Suite struct DetectorTests {
    /// Built at runtime (no token-looking literal in the repo): header {"alg":"HS256","typ":"JWT"},
    /// payload {"sub":"usr_8f2c41","role":"doctor","iat":1762156800,"exp":1762171200}, fake signature.
    static let jwt: String = {
        func b64url(_ s: String) -> String {
            Data(s.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return [b64url(#"{"alg":"HS256","typ":"JWT"}"#),
                b64url(#"{"sub":"usr_8f2c41","role":"doctor","iat":1762156800,"exp":1762171200}"#),
                b64url("not-a-real-signature")].joined(separator: ".")
    }()

    @Test func jwtDecodes() throws {
        guard case .jwt(let h, let p, let iat, let exp)? = Detectors.detect(Self.jwt).first else { Issue.record("not a JWT"); return }
        #expect(h.contains("\"alg\" : \"HS256\""))
        #expect(p.contains("\"role\" : \"doctor\""))
        #expect(iat == Date(timeIntervalSince1970: 1_762_156_800))
        #expect(exp == Date(timeIntervalSince1970: 1_762_171_200))
        #expect(SecretDetector.isSecret(Self.jwt))
    }

    @Test func json() {
        guard case .json(let pretty, let mini, let keys)? = Detectors.detect(#"{"status":"ok","latency_ms":182}"#).first else { Issue.record(); return }
        #expect(keys == 2)
        #expect(mini == #"{"latency_ms":182,"status":"ok"}"#)
        #expect(pretty.contains("\n"))
        #expect(Detectors.detect("{not json").isEmpty)
    }

    @Test func timestamps() {
        #expect(Detectors.detect("1762160400") == [.timestamp(t0)])
        #expect(Detectors.detect("1762160400000") == [.timestamp(t0)])
        #expect(Detectors.detect("1234567890123456").isEmpty)    // not 10/13 digits
        #expect(Detectors.detect("0000000001").isEmpty)          // year 1970
    }

    @Test func others() {
        #expect(Detectors.detect("a3f1c9e2-5b7d-4e8a-9c1f-2d6b8e0a4f73") == [.uuid("a3f1c9e2-5b7d-4e8a-9c1f-2d6b8e0a4f73")])
        #expect(Detectors.detect("#FF9F0A") == [.hexColor(PickedColor(hex: "#FF9F0A")!)])
        #expect(Detectors.detect("https://github.com/telekonsul/api-gateway/pull/482") == [.url(URL(string: "https://github.com/telekonsul/api-gateway/pull/482")!)])
        #expect(Detectors.detect("~/dev/api-gateway/.env.example") == [.path("~/dev/api-gateway/.env.example")])
        #expect(Detectors.detect("hello%20world%21") == [.urlEncoded("hello world!")])
        #expect(Detectors.detect("aGVsbG8gZHlsYW4=") == [.base64("hello dylan")])
        #expect(Detectors.detect("just some words").isEmpty)
        #expect(Detectors.detect("deadbeef").isEmpty)   // base64-looking but not readable text
    }
}

@Suite struct SecretTests {
    @Test(arguments: ["ghp_abcdefghijklmnopqrstuvwxyz0123456789a1b2", "github_pat_11ABCDEFG0123456789_abcdefghij",
                      "sk-ant-api03-abcdefghijk", "sk-proj-abcdefghijklmnopqrst", "AKIAIOSFODNN7EXAMPLE",
                      "xoxb-123456789012-abcdefghij", "-----BEGIN OPENSSH PRIVATE KEY-----\nabc", "password=hunter2", "API_KEY: abc123",
                      "export GITHUB_TOKEN=ghp_abcdefghijklmnopqrstuvwxyz0123", "OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrst",
                      "DB_PASSWORD=hunter2", "aws_access_key_id = AKIAIOSFODNN7EXAMPLE", "Authorization: Bearer abcdefghijklmnop.qrs",
                      "DATABASE_URL=postgres://app:hunter2@db.local/app", "\"client_secret\": \"abc\"", "line one\nghp_abcdefghijklmnopqrstuvwxyz0123\n"])
    func secrets(_ s: String) { #expect(SecretDetector.isSecret(s)) }

    @Test(arguments: ["hello", "ghp is short", "skeleton-key", "https://example.com/token", "task-abcdefghijklmnopqrstuv",
                      "https://user@example.com/path", "the token is ready", "Bearer of bad news", "AKIAIOSFODNN7EXAMPLEXYZ"])
    func notSecrets(_ s: String) { #expect(!SecretDetector.isSecret(s)) }

    @Test func masking() {
        #expect(SecretDetector.mask("ghp_abcdefghijklmnopqrstuvwxyz0123456789a1b2") == "ghp_••••a1b2")
        #expect(SecretDetector.mask("AKIAIOSFODNN7EXAMPLE") == "AKIA••••MPLE")
        #expect(SecretDetector.mask("short") == "•••••")
        #expect(SecretDetector.mask("password=hunter2_x1") == "pass••••2_x1")
    }

    @Test func generators() {
        #expect(Generators.hashes("abc").md5 == "900150983cd24fb0d6963f7d28e17f72")
        #expect(Generators.hashes("abc").sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(Generators.timestamps(t0).seconds == "1762160400")
        #expect(Generators.timestamps(t0).iso == "2025-11-03T09:00:00Z")   // the design's sample value is a 2025 timestamp
        #expect(Generators.uuid().count == 36)
    }
}

@Suite struct ClipboardHistoryTests {
    typealias Item = ClipboardHistory.Item

    @Test func dedupeAndLimit() {
        var h = ClipboardHistory(); h.limit = 3
        for i in 0..<5 { h.add(Item(kind: .text, text: "t\(i)", date: t0.addingTimeInterval(Double(i)))) }
        #expect(h.items.map(\.text) == ["t4", "t3", "t2"])
        h.add(Item(kind: .text, text: "t2", date: t0.addingTimeInterval(10)))
        #expect(h.items.map(\.text) == ["t2", "t4", "t3"])
    }

    @Test func secretsExpireAndNeverPersist() {
        var h = ClipboardHistory()
        h.add(Item(kind: .text, text: "ghp_x", date: t0, secret: true))
        h.add(Item(kind: .text, text: "hello", date: t0))
        #expect(h.persistable.items.map(\.text) == ["hello"])
        h.trim(now: t0.addingTimeInterval(119))
        #expect(h.items.count == 2)
        h.trim(now: t0.addingTimeInterval(120))
        #expect(h.items.map(\.text) == ["hello"])
        #expect(h.search("ghp").isEmpty)
    }

    @Test func pinnedSurviveAgeAndLimit() {
        var h = ClipboardHistory(); h.limit = 1
        h.add(Item(kind: .text, text: "keep", date: t0))
        h.togglePin(h.items[0].id)
        h.add(Item(kind: .text, text: "a", date: t0.addingTimeInterval(1)))
        h.add(Item(kind: .text, text: "b", date: t0.addingTimeInterval(2)))
        #expect(h.items.map(\.text) == ["b", "keep"])
        h.trim(now: t0.addingTimeInterval(40 * 24 * 3600))
        #expect(h.items.map(\.text) == ["keep"])
        #expect(h.search("", pinnedOnly: true).count == 1)
    }
}
