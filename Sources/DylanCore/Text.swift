import Foundation

/// Truncation rules from the design handoff ("Aturan pemotongan teks").
public enum TextRules {
    public static func singleLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Sentences: cut at the tail.
    public static func truncateTail(_ s: String, max: Int) -> String {
        guard s.count > max, max > 1 else { return s }
        return String(s.prefix(max - 1)) + "…"
    }

    /// File names: cut in the middle, extension always visible ("AuthSer…ce.swift").
    public static func truncateMiddle(_ s: String, max: Int) -> String {
        guard s.count > max, max > 4 else { return s }
        let ext = (s as NSString).pathExtension
        let suffixKeep = ext.isEmpty ? (max - 1) / 2 : min(ext.count + 3, max / 2)
        let prefixKeep = max - 1 - suffixKeep
        return String(s.prefix(prefixKeep)) + "…" + String(s.suffix(suffixKeep))
    }

    /// Paths: `/Users/<u>` becomes `~`, then cut in the middle.
    public static func abbreviatePath(_ path: String, home: String = NSHomeDirectory(), max: Int = 60) -> String {
        var p = path
        if p == home { p = "~" } else if p.hasPrefix(home + "/") { p = "~" + p.dropFirst(home.count) }
        return truncateMiddle(p, max: max)
    }

    /// First sentence of an assistant reply, single line, ≤ 120 chars.
    public static func firstSentence(_ s: String) -> String {
        let line = s.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("```") } ?? ""
        let cleaned = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        if let r = cleaned.range(of: #"[.!?](\s|$)"#, options: .regularExpression) {
            return truncateTail(String(cleaned[..<r.upperBound]).trimmingCharacters(in: .whitespaces), max: 120)
        }
        return truncateTail(cleaned, max: 120)
    }

    /// Compact shows the first word plus the sub-command: `npm test`, `cargo build`.
    /// Package-manager scripts show the script name: `npm run build` → `build`.
    public static func commandShortName(_ cmd: String) -> String {
        let words = Array(singleLine(cmd).split(separator: " ").map(String.init)
            .drop { $0.range(of: #"^[A-Za-z_][A-Za-z0-9_]*="#, options: .regularExpression) != nil })  // `FOO=bar cmd`
        guard let first = words.first else { return "" }
        let tool = (first as NSString).lastPathComponent
        if ["npm", "pnpm", "yarn", "bun"].contains(tool), words.count >= 3, words[1] == "run" { return words[2] }
        if words.count >= 2, !words[1].hasPrefix("-"), words[1].count <= 16 { return "\(tool) \(words[1])" }
        return tool
    }
}

/// Number formats from the design handoff ("Format angka · digit tabular").
public enum DurationFormat {
    /// Result durations: `48s`, `4m 12s`, `1h 05m`.
    public static func result(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(String(format: "%02d", s % 60))s" }
        return "\(s / 3600)h \(String(format: "%02d", (s % 3600) / 60))m"
    }

    /// Running clocks: `0:10`, `1:23`, `1:02:03`.
    public static func running(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 3600 { return "\(s / 60):\(String(format: "%02d", s % 60))" }
        return "\(s / 3600):\(String(format: "%02d", (s % 3600) / 60)):\(String(format: "%02d", s % 60))"
    }

    /// Meeting countdown: `10m` while ≥ 1 minute (rounded up), then `0:58`.
    public static func countdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        if s >= 60 { return "\(Int((Double(s) / 60).rounded(.up)))m" }
        return "0:\(String(format: "%02d", s))"
    }

    /// Long, localized: `1 j 20 m` (id) / `1 h 20 m` (en); minutes only: `38 m`.
    public static func long(_ seconds: TimeInterval, language: String) -> String {
        let m = max(0, Int((seconds / 60).rounded()))
        let hour = language.hasPrefix("id") ? "j" : "h"
        if m < 60 { return "\(m) m" }
        return m % 60 == 0 ? "\(m / 60) \(hour)" : "\(m / 60) \(hour) \(m % 60) m"
    }

    /// `+120 −8` (true minus sign, as in the design).
    public static func diff(added: Int, removed: Int) -> String { "+\(added) \u{2212}\(removed)" }
}
