import CryptoKit
import Foundation

/// Clipboard smart detect (FR-21) and secret protection (FR-22, PRD §2.8).
public enum Detected: Equatable, Sendable {
    case json(pretty: String, minified: String, keys: Int)
    case jwt(header: String, payload: String, issuedAt: Date?, expires: Date?)
    case timestamp(Date)
    case base64(String)
    case urlEncoded(String)
    case uuid(String)
    case hexColor(PickedColor)
    case url(URL)
    case path(String)
}

public enum Detectors {
    /// Most specific first; returns every match that applies (a JWT is also "secret").
    public static func detect(_ raw: String, now: Date = Date()) -> [Detected] {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 200_000 else { return [] }
        var out: [Detected] = []
        if let j = jwt(s) { out.append(j) }
        if let j = json(s) { out.append(j) }
        if let t = timestamp(s) { out.append(.timestamp(t)) }
        if s.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#, options: .regularExpression) != nil {
            out.append(.uuid(s))
        }
        if s.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil, let c = PickedColor(hex: s) { out.append(.hexColor(c)) }
        if let u = URL(string: s), let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme), u.host != nil, !s.contains(" ") {
            out.append(.url(u))
        }
        if s.hasPrefix("/") || s.hasPrefix("~/"), !s.contains("\n"), s.count < 1024 { out.append(.path(s)) }
        if s.contains("%"), let d = s.removingPercentEncoding, d != s, !out.contains(where: { if case .url = $0 { return true }; return false }) {
            out.append(.urlEncoded(d))
        }
        if out.isEmpty, let b = base64Text(s) { out.append(.base64(b)) }
        return out
    }

    // MARK: JSON

    static func json(_ s: String) -> Detected? {
        guard let first = s.first, first == "{" || first == "[",
              let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let mini = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        let keys = (obj as? [String: Any])?.count ?? (obj as? [Any])?.count ?? 0
        return .json(pretty: String(decoding: pretty, as: UTF8.self), minified: String(decoding: mini, as: UTF8.self), keys: keys)
    }

    // MARK: JWT

    static func base64URLDecode(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }

    public static func jwt(_ s: String) -> Detected? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, s.hasPrefix("eyJ"), !s.contains(" "),
              let h = base64URLDecode(String(parts[0])), let p = base64URLDecode(String(parts[1])),
              let hObj = try? JSONSerialization.jsonObject(with: h), let pObj = try? JSONSerialization.jsonObject(with: p) as? [String: Any],
              let hPretty = try? JSONSerialization.data(withJSONObject: hObj, options: [.prettyPrinted, .sortedKeys]),
              let pPretty = try? JSONSerialization.data(withJSONObject: pObj, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        func date(_ k: String) -> Date? { (pObj[k] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } }
        return .jwt(header: String(decoding: hPretty, as: UTF8.self), payload: String(decoding: pPretty, as: UTF8.self),
                    issuedAt: date("iat"), expires: date("exp"))
    }

    // MARK: Timestamp (10 or 13 digits, year 2000–2100)

    static func timestamp(_ s: String) -> Date? {
        guard s.allSatisfy(\.isNumber), s.count == 10 || s.count == 13, let v = Double(s) else { return nil }
        let d = Date(timeIntervalSince1970: s.count == 13 ? v / 1000 : v)
        let year = Calendar(identifier: .gregorian).component(.year, from: d)
        return (2000...2100).contains(year) ? d : nil
    }

    // MARK: Base64 → readable UTF-8 only

    static func base64Text(_ s: String) -> String? {
        guard s.count >= 8, s.count % 4 == 0, s.range(of: #"^[A-Za-z0-9+/]+={0,2}$"#, options: .regularExpression) != nil,
              let d = Data(base64Encoded: s), let t = String(data: d, encoding: .utf8),
              !t.isEmpty, t.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\t" }) else { return nil }
        return t
    }
}

/// Secrets never reach the history file; they live in memory, masked, for 2 minutes (PRD §2.8).
public enum SecretDetector {
    static let patterns: [String] = [
        #"^gh[pousr]_[A-Za-z0-9]{20,}$"#, #"^github_pat_[A-Za-z0-9_]{20,}$"#,
        #"^sk-ant-[A-Za-z0-9_\-]{10,}$"#, #"^sk-[A-Za-z0-9_\-]{16,}$"#,
        #"^AKIA[0-9A-Z]{16}$"#, #"^xox[abposr]-[A-Za-z0-9-]{10,}$"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
        #"(?i)\b(password|passwd|token|secret|api[_-]?key)\s*[=:]\s*\S+"#,
    ]
    public static let ttl: TimeInterval = 120

    /// Pasteboard types password managers set (nspasteboard.org conventions).
    public static let skippedTypes: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
    ]

    public static let defaultIgnoredApps: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.apple.keychainaccess", "com.apple.Passwords",
    ]

    public static func isSecret(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .jwt? = Detectors.jwt(s) { return true }
        return patterns.contains { s.range(of: $0, options: .regularExpression) != nil }
    }

    /// `ghp_••••a1b2`: keep a short prefix and the last 4 characters.
    public static func mask(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count > 8 else { return String(repeating: "•", count: s.count) }
        let prefix = s.firstIndex(of: "_").map { String(s[...$0]) } ?? String(s.prefix(4))
        return prefix + "••••" + String(s.suffix(4))
    }
}

/// Generators in the Clipboard tab.
public enum Generators {
    public static func uuid() -> String { UUID().uuidString.lowercased() }

    public static func timestamps(_ d: Date) -> (seconds: String, millis: String, iso: String) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return (String(Int(d.timeIntervalSince1970)), String(Int(d.timeIntervalSince1970 * 1000)), iso.string(from: d))
    }

    public static func hashes(_ s: String) -> (md5: String, sha1: String, sha256: String) {
        let d = Data(s.utf8)
        func hex<D: Sequence>(_ x: D) -> String where D.Element == UInt8 { x.map { String(format: "%02x", $0) }.joined() }
        return (hex(Insecure.MD5.hash(data: d)), hex(Insecure.SHA1.hash(data: d)), hex(SHA256.hash(data: d)))
    }
}

/// Clipboard history rules: size and age limits; pinned items never expire. FR-20.
public struct ClipboardHistory: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public enum Kind: String, Codable, Sendable { case text, image, file }
        public var id: UUID
        public var kind: Kind
        public var text: String          // text, or file path(s), or "Image 1280×720"
        public var date: Date
        public var pinned: Bool
        public var sourceApp: String?
        /// Secrets are kept only in memory and dropped after `SecretDetector.ttl`.
        public var secret: Bool
        public init(id: UUID = UUID(), kind: Kind, text: String, date: Date, pinned: Bool = false, sourceApp: String? = nil, secret: Bool = false) {
            self.id = id; self.kind = kind; self.text = text; self.date = date; self.pinned = pinned; self.sourceApp = sourceApp; self.secret = secret
        }
    }

    public var items: [Item] = []
    public var limit = 500
    public var maxAge: TimeInterval = 30 * 24 * 3600
    public init() {}

    /// Adds a copy; the same text moves to the top instead of duplicating.
    public mutating func add(_ item: Item) {
        if let i = items.firstIndex(where: { $0.kind == item.kind && $0.text == item.text }) {
            var existing = items.remove(at: i)
            existing.date = item.date
            existing.secret = item.secret
            items.insert(existing, at: 0)
        } else {
            items.insert(item, at: 0)
        }
        trim(now: item.date)
    }

    public mutating func trim(now: Date) {
        items.removeAll { !$0.pinned && ($0.secret ? now.timeIntervalSince($0.date) >= SecretDetector.ttl : now.timeIntervalSince($0.date) >= maxAge) }
        var unpinned = 0
        items.removeAll { item in
            guard !item.pinned else { return false }
            unpinned += 1
            return unpinned > limit
        }
    }

    public mutating func togglePin(_ id: UUID) {
        if let i = items.firstIndex(where: { $0.id == id }), !items[i].secret { items[i].pinned.toggle() }
    }

    /// What may be written to disk: never secrets.
    public var persistable: ClipboardHistory {
        var c = self
        c.items = items.filter { !$0.secret }
        return c
    }

    public func search(_ q: String, kind: Item.Kind? = nil, pinnedOnly: Bool = false) -> [Item] {
        let ql = q.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { i in
            (kind == nil || i.kind == kind) && (!pinnedOnly || i.pinned) && (ql.isEmpty || (!i.secret && i.text.lowercased().contains(ql)))
        }
    }
}
