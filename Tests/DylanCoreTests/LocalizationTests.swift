import Foundation
import Testing

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
}
