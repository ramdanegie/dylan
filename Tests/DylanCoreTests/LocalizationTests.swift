import Foundation
import Testing
@testable import DylanCore

/// FR-18 AC: no untranslated strings. Both languages have the same keys and the same format arguments,
/// and every `L("…")` key used in the app exists.
@Suite struct LocalizationTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let resources = root.appendingPathComponent("Sources/Dylan/Resources")

    static func strings(_ lang: String) throws -> [String: String] {
        let url = resources.appendingPathComponent("\(lang).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    static func specifiers(_ s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(?:l?d|@)"#)
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range).replacingOccurrences(of: #"\d+\$"#, with: "", options: .regularExpression) }
            .sorted()
    }

    @Test func sameKeysAndArguments() throws {
        let id = try Self.strings("id"), en = try Self.strings("en")
        #expect(Set(id.keys) == Set(en.keys))
        for (k, v) in id {
            #expect(Self.specifiers(v) == Self.specifiers(en[k] ?? ""), "format arguments differ for \(k)")
            #expect(!v.isEmpty && !(en[k] ?? "").isEmpty, "empty translation for \(k)")
        }
    }

    @Test func everyUsedKeyExists() throws {
        let keys = Set(try Self.strings("id").keys)
        let src = Self.root.appendingPathComponent("Sources/Dylan")
        let re = try NSRegularExpression(pattern: #"L\("([A-Za-z0-9_.]+)""#)
        var missing: [String] = []
        for case let url as URL in FileManager.default.enumerator(at: src, includingPropertiesForKeys: nil)! where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let k = String(text[Range(m.range(at: 1), in: text)!])
                if !keys.contains(k) { missing.append("\(url.lastPathComponent): \(k)") }
            }
        }
        #expect(missing.isEmpty, "\(missing)")
    }

    @Test func featureCatalogCoversPRD() throws {
        let prd = try String(contentsOf: Self.root.appendingPathComponent("PRD.md"), encoding: .utf8)
        let re = try NSRegularExpression(pattern: #"(?m)^\| (FR-\d+) \|"#)
        let inPRD = Set(re.matches(in: prd, range: NSRange(prd.startIndex..., in: prd)).map { String(prd[Range($0.range(at: 1), in: prd)!]) })
        let covered = Set(FeatureSupport.all.flatMap(\.requirements))
        #expect(!inPRD.isEmpty)
        #expect(covered == inPRD, "missing: \(inPRD.subtracting(covered).sorted()) extra: \(covered.subtracting(inPRD).sorted())")
        #expect(Set(FeatureSupport.all.map(\.id)).count == FeatureSupport.all.count)
        for lang in ["id", "en"] {
            let strings = try Self.strings(lang)
            for f in FeatureSupport.all {
                #expect(strings["support.\(f.id)"] != nil && strings["support.\(f.id).desc"] != nil, "\(lang): \(f.id)")
                #expect((strings["support.\(f.id).req"] != nil) == f.hasRequirement, "\(lang): \(f.id).req")
            }
        }
    }

    @Test func featureStatusRules() {
        let byID = Dictionary(uniqueKeysWithValues: FeatureSupport.all.map { ($0.id, $0) })
        #expect(byID["faceUnlock"]?.status(macOSMajor: 27) == .experimental)
        #expect(byID["lockScreen"]?.status(macOSMajor: 27) == .experimental)
        #expect(byID["claudeSessions"]?.status(macOSMajor: 27) == .available)
        #expect(byID["discordVoice"]?.status(macOSMajor: 27) == .soon)      // next release
        #expect(byID["otherPlayers"]?.status(macOSMajor: 27) == .soon)      // unfinished v1.0 scope
        #expect(byID["downloads"]?.status(macOSMajor: 27) == .planned)
        #expect(byID["weather"]?.status(macOSMajor: 27) == .available)
    }
}
