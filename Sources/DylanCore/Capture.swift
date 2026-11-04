import CoreGraphics
import Foundation

/// Screenshot selection math (FR-88, design D39). Points are in one screen's coordinates.
public enum CaptureSelection {
    /// The rectangle dragged from `a` to `b`. ⇧ locks `ratio` (width/height, 1 = square), ⌥ grows from `a` as
    /// the center. The result is clamped to `bounds` and has whole-point edges.
    public static func rect(from a: CGPoint, to b: CGPoint, lockRatio ratio: CGFloat? = nil, fromCenter: Bool = false,
                            bounds: CGRect) -> CGRect {
        var dx = b.x - a.x, dy = b.y - a.y
        if let ratio, ratio > 0 {
            // Keep the larger drag direction and derive the other from the ratio, keeping the drag's signs.
            let w = max(abs(dx), abs(dy) * ratio)
            dx = w * (dx < 0 ? -1 : 1)
            dy = w / ratio * (dy < 0 ? -1 : 1)
        }
        let r = fromCenter
            ? CGRect(x: a.x - abs(dx), y: a.y - abs(dy), width: abs(dx) * 2, height: abs(dy) * 2)
            : CGRect(x: min(a.x, a.x + dx), y: min(a.y, a.y + dy), width: abs(dx), height: abs(dy))
        return r.intersection(bounds).integral
    }

    /// Arrow keys move the selection by one point (⇧ = 10), never outside the screen.
    public static func nudge(_ r: CGRect, dx: CGFloat, dy: CGFloat, bounds: CGRect) -> CGRect {
        var o = r.offsetBy(dx: dx, dy: dy)
        o.origin.x = min(max(o.minX, bounds.minX), bounds.maxX - o.width)
        o.origin.y = min(max(o.minY, bounds.minY), bounds.maxY - o.height)
        return o
    }

    /// A rect in a screen's points (AppKit, origin bottom-left) → the matching pixel rect in that screen's image
    /// (origin top-left).
    public static func pixelRect(_ r: CGRect, screen: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: (r.minX - screen.minX) * scale, y: (screen.maxY - r.maxY) * scale,
               width: r.width * scale, height: r.height * scale).integral
    }

    /// Too small to be a deliberate drag: treat as a click (window / screen pick).
    public static func isClick(_ r: CGRect) -> Bool { r.width < 4 || r.height < 4 }
}

/// Where captures go and how long they stay (FR-89, design D43).
public enum CaptureStore {
    public static let defaultRetentionDays = 30

    /// "Dylan 2026-11-04 09.41.png" (design), in the user's local time.
    public static func fileName(_ date: Date, ext: String = "png", calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return "Dylan \(f.string(from: date)).\(ext)"
    }

    /// Files older than the retention window (0 = keep forever).
    public static func expired(_ files: [(path: String, date: Date)], now: Date, days: Int) -> [String] {
        guard days > 0 else { return [] }
        let limit = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        return files.filter { $0.date < limit }.map(\.path)
    }

    /// "142 capture · 86 MB" style numbers for Settings.
    public static func summary(count: Int, bytes: Int64) -> (count: Int, megabytes: Int) {
        (count, Int((Double(bytes) / 1_048_576).rounded()))
    }
}

/// Scrolling capture (FR-91, design D42): each frame is reduced to one hash per pixel row; the next frame is
/// placed where its rows continue the previous one. Rows at the top that never change between frames are a
/// sticky header and are not repeated.
public enum ScrollStitch {
    public static let maxHeight = 20_000

    /// Rows identical at the top of both frames (sticky header / toolbar).
    public static func stickyRows(_ prev: [UInt64], _ next: [UInt64]) -> Int {
        var n = 0
        while n < min(prev.count, next.count), prev[n] == next[n] { n += 1 }
        // A frame that did not scroll at all is not a header.
        return n == min(prev.count, next.count) ? 0 : n
    }

    /// Rows identical at the bottom of both frames (sticky footer / cookie bar).
    public static func stickyFooterRows(_ prev: [UInt64], _ next: [UInt64]) -> Int {
        var n = 0
        while n < min(prev.count, next.count), prev[prev.count - 1 - n] == next[next.count - 1 - n] { n += 1 }
        return n == min(prev.count, next.count) ? 0 : n
    }

    /// How far `next` scrolled relative to `prev` (rows), comparing between the sticky header and footer.
    /// nil = no match (scrolled too far between frames), no movement, or a blank area that matches anywhere.
    public static func shift(_ prev: [UInt64], _ next: [UInt64], sticky: Int = 0, footer: Int = 0, minOverlap: Int = 24) -> Int? {
        let h = min(prev.count, next.count) - footer
        guard h - sticky > minOverlap, prev != next else { return nil }
        // A uniform region (blank page) would "match" at shift 1 forever.
        guard Set(next[sticky..<h]).count > 1 else { return nil }
        // Look for the largest overlap first: small scroll steps are the common case.
        for s in 1...(h - sticky - minOverlap) {
            var ok = true
            var i = sticky
            while i + s < h {
                if prev[i + s] != next[i] { ok = false; break }
                i += 1
            }
            if ok { return s }
        }
        return nil
    }

    /// Rows of `next` to append after a shift of `s` rows: the newly revealed bottom part.
    public static func newRows(height: Int, shift s: Int) -> Range<Int> { max(0, height - s)..<height }
}
