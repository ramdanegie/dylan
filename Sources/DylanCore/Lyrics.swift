import Foundation

/// Synced lyrics in LRC format (FR-62, PRD §F5). Source: LRCLIB (`syncedLyrics`).
public struct Lyrics: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public var time: TimeInterval
        public var text: String
    }

    public var lines: [Line]
    /// Plain lyrics have no timing; the UI shows them without highlighting.
    public var synced: Bool

    public init(lines: [Line], synced: Bool) { self.lines = lines; self.synced = synced }

    /// Parses `[mm:ss.xx]text`, several tags per line, and `[offset:±ms]`. Metadata tags are ignored.
    public static func parseLRC(_ lrc: String) -> Lyrics {
        var offset: TimeInterval = 0
        var out: [Line] = []
        let tag = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]"#)
        for raw in lrc.split(whereSeparator: \.isNewline).map(String.init) {
            if let r = raw.range(of: #"^\[offset:\s*([+-]?\d+)\]"#, options: .regularExpression) {
                offset = (Double(raw[r].filter { $0.isNumber || $0 == "-" || $0 == "+" }) ?? 0) / 1000
                continue
            }
            let ns = raw as NSString
            let matches = tag.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.upperBound).trimmingCharacters(in: .whitespaces)
            for m in matches {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                // A positive offset makes lyrics appear earlier (LRC convention).
                out.append(Line(time: max(0, min * 60 + sec - offset), text: text))
            }
        }
        return Lyrics(lines: out.sorted { $0.time < $1.time }, synced: true)
    }

    public static func plain(_ text: String) -> Lyrics {
        Lyrics(lines: text.split(whereSeparator: \.isNewline).map { Line(time: 0, text: String($0)) }, synced: false)
    }

    /// Index of the line being sung at `position`, or nil before the first line.
    public func index(at position: TimeInterval) -> Int? {
        guard synced, let first = lines.first, position >= first.time else { return nil }
        var lo = 0, hi = lines.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lines[mid].time <= position { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// LRCLIB request for a track (duration in whole seconds helps it pick the right version).
    public static func lrclibURL(title: String, artist: String, album: String, duration: TimeInterval) -> URL? {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist),
                        URLQueryItem(name: "album_name", value: album), URLQueryItem(name: "duration", value: String(Int(duration.rounded())))]
        return c.url
    }

    /// Decodes an LRCLIB response; nil when there is nothing to show (instrumental or empty).
    public static func fromLRCLIB(_ data: Data) -> Lyrics? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if o["instrumental"] as? Bool == true { return nil }
        if let s = o["syncedLyrics"] as? String, !s.isEmpty { let l = parseLRC(s); return l.lines.isEmpty ? nil : l }
        if let p = o["plainLyrics"] as? String, !p.isEmpty { return plain(p) }
        return nil
    }
}

/// Spotify links pinned for quick play (FR-60): `open.spotify.com/playlist/<id>` → `spotify:playlist:<id>`.
public enum SpotifyLink {
    public static func uri(from input: String) -> String? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.range(of: #"^spotify:(playlist|album|artist|track|show):[A-Za-z0-9]{10,}$"#, options: .regularExpression) != nil { return s }
        guard let u = URL(string: s), u.host?.hasSuffix("spotify.com") == true else { return nil }
        let parts = u.path.split(separator: "/").map(String.init).filter { !$0.hasPrefix("intl-") }
        guard parts.count >= 2, ["playlist", "album", "artist", "track", "show"].contains(parts[0]),
              parts[1].range(of: #"^[A-Za-z0-9]{10,}$"#, options: .regularExpression) != nil else { return nil }
        return "spotify:\(parts[0]):\(parts[1])"
    }
}
