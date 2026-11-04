import Foundation

/// "0.1.2", "v1.1.1", "1.2.0-beta.1" → comparable numbers. The pre-release suffix sorts before the plain version.
public struct SemVer: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]
    public let prerelease: String?

    public init?(_ s: String) {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
        let split = t.split(separator: "-", maxSplits: 1)
        guard let core = split.first else { return nil }
        let nums = core.split(separator: ".").map { Int($0) }
        guard !nums.isEmpty, nums.count <= 4, nums.allSatisfy({ $0 != nil }) else { return nil }
        parts = nums.map { $0! } + Array(repeating: 0, count: 3 - min(3, nums.count))
        prerelease = split.count > 1 ? String(split[1]) : nil
    }

    public var description: String { parts.prefix(3).map(String.init).joined(separator: ".") + (prerelease.map { "-\($0)" } ?? "") }

    public static func < (a: SemVer, b: SemVer) -> Bool {
        for (x, y) in zip(a.parts, b.parts) where x != y { return x < y }
        if a.parts.count != b.parts.count { return a.parts.count < b.parts.count }
        switch (a.prerelease, b.prerelease) {
        case (nil, _): return false
        case (_, nil): return true
        case let (x?, y?): return x.compare(y, options: .numeric) == .orderedAscending
        }
    }

    public static func == (a: SemVer, b: SemVer) -> Bool { a.parts == b.parts && a.prerelease == b.prerelease }
}

/// One GitHub release (`GET /repos/{owner}/{repo}/releases`), only the fields the update check needs.
public struct ReleaseInfo: Decodable, Equatable, Sendable {
    public struct Asset: Decodable, Equatable, Sendable {
        public let name: String
        public let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey { case name, browserDownloadURL = "browser_download_url" }
    }

    public let tag: String
    public let name: String?
    public let body: String?
    public let draft: Bool
    public let prerelease: Bool
    public let htmlURL: URL
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name", name, body, draft, prerelease, htmlURL = "html_url", assets
    }

    public init(tag: String, name: String? = nil, body: String? = nil, draft: Bool = false, prerelease: Bool = false,
                htmlURL: URL, assets: [Asset] = []) {
        self.tag = tag; self.name = name; self.body = body; self.draft = draft; self.prerelease = prerelease
        self.htmlURL = htmlURL; self.assets = assets
    }

    public var version: SemVer? { SemVer(tag) }
    /// The DMG to download, else the release page.
    public var downloadURL: URL { assets.first { $0.name.lowercased().hasSuffix(".dmg") }?.browserDownloadURL ?? htmlURL }
}

public enum Updates {
    /// The newest published release above `current`, skipping drafts, the version the user skipped, and
    /// pre-releases unless asked for (an app whose releases are all pre-releases passes `true`).
    public static func newest(_ releases: [ReleaseInfo], current: String, skipped: String? = nil, includePrerelease: Bool) -> ReleaseInfo? {
        guard let now = SemVer(current) else { return nil }
        let skip = skipped.flatMap(SemVer.init)
        return releases
            .filter { !$0.draft && (includePrerelease || !$0.prerelease) }
            .compactMap { r in r.version.map { (r, $0) } }
            .filter { $0.1 > now && $0.1 != skip }
            .max { $0.1 < $1.1 }?.0
    }

    /// Automatic checks at most once a day; a manual "Check now" always runs.
    public static func isDue(lastCheck: Date?, now: Date, interval: TimeInterval = 24 * 3600) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval || now < lastCheck
    }
}

/// Keep-a-Changelog style markdown: `## [0.1.2] - 2026-11-04` headings.
public enum Changelog {
    /// The lines under the heading for `version` (without the heading), or nil.
    public static func section(_ markdown: String, version: String) -> String? {
        guard let want = SemVer(version) else { return nil }
        var out: [Substring] = [], inside = false
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                if inside { break }
                let label = line.dropFirst(3).split(separator: " ").first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) } ?? ""
                inside = SemVer(label) == want
                continue
            }
            if inside { out.append(line) }
        }
        let text = out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Shown once after an update: the stored version differs from the running one (not on a first install).
    public static func shouldShowWhatsNew(lastSeen: String?, current: String) -> Bool {
        guard let lastSeen, let a = SemVer(lastSeen), let b = SemVer(current) else { return false }
        return b > a
    }
}
