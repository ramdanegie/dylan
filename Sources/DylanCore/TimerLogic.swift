import Foundation

/// Quick timer and Pomodoro, based on the wall clock so they stay correct across sleep. PRD §F7.
public struct CountdownTimer: Equatable, Sendable {
    public enum Phase: String, Sendable, Codable { case timer, focus, shortBreak, longBreak }

    public var phase: Phase
    public var duration: TimeInterval
    public var endsAt: Date?
    /// Remaining time while paused.
    public var pausedRemaining: TimeInterval?
    /// Completed focus sessions in the current Pomodoro cycle (0…4).
    public var focusCount: Int

    public static let focus: TimeInterval = 25 * 60
    public static let shortBreak: TimeInterval = 5 * 60
    public static let longBreak: TimeInterval = 15 * 60

    public static func quick(_ duration: TimeInterval, now: Date) -> CountdownTimer {
        CountdownTimer(phase: .timer, duration: duration, endsAt: now.addingTimeInterval(duration), pausedRemaining: nil, focusCount: 0)
    }

    public static func pomodoro(now: Date) -> CountdownTimer {
        CountdownTimer(phase: .focus, duration: focus, endsAt: now.addingTimeInterval(focus), pausedRemaining: nil, focusCount: 0)
    }

    public func remaining(now: Date) -> TimeInterval {
        if let p = pausedRemaining { return p }
        guard let e = endsAt else { return 0 }
        return max(0, e.timeIntervalSince(now))
    }

    public func progress(now: Date) -> Double {
        duration > 0 ? 1 - remaining(now: now) / duration : 1
    }

    public var isPaused: Bool { pausedRemaining != nil }

    public mutating func pause(now: Date) {
        guard pausedRemaining == nil else { return }
        pausedRemaining = remaining(now: now)
        endsAt = nil
    }

    public mutating func resume(now: Date) {
        guard let p = pausedRemaining else { return }
        endsAt = now.addingTimeInterval(p)
        pausedRemaining = nil
    }

    public func isFinished(now: Date) -> Bool { !isPaused && remaining(now: now) <= 0 }

    /// Next Pomodoro phase after the current one ends: every 4th break is long. Quick timers return nil.
    public func next(now: Date) -> CountdownTimer? {
        switch phase {
        case .timer:
            return nil
        case .focus:
            let count = focusCount + 1
            let long = count % 4 == 0
            let d = long ? Self.longBreak : Self.shortBreak
            return CountdownTimer(phase: long ? .longBreak : .shortBreak, duration: d,
                                  endsAt: now.addingTimeInterval(d), pausedRemaining: nil, focusCount: count)
        case .shortBreak, .longBreak:
            return CountdownTimer(phase: .focus, duration: Self.focus, endsAt: now.addingTimeInterval(Self.focus),
                                  pausedRemaining: nil, focusCount: focusCount % 4)
        }
    }
}

/// Parses free timer input: `45m`, `1h30`, `1h 30m`, `90s`, `10` (minutes), `1:30` (m:ss).
public enum DurationParser {
    public static func parse(_ input: String) -> TimeInterval? {
        let s = input.lowercased().replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return nil }
        if let m = Int(s) { return m > 0 ? TimeInterval(m * 60) : nil }
        if s.contains(":") {
            let p = s.split(separator: ":").compactMap { Int($0) }
            guard p.count == 2, p[1] < 60 else { return nil }
            let t = TimeInterval(p[0] * 60 + p[1]); return t > 0 ? t : nil
        }
        // Tokens like `1h`, `30m`, `90s`; a bare number after hours means minutes (`1h30`).
        guard let re = try? NSRegularExpression(pattern: #"(\d+)([hjms]?)"#) else { return nil }
        let ns = s as NSString
        var total: TimeInterval = 0, consumed = 0, lastUnit = ""
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            guard m.range.location == consumed else { return nil }
            consumed += m.range.length
            let n = TimeInterval(Int(ns.substring(with: m.range(at: 1))) ?? 0)
            var unit = ns.substring(with: m.range(at: 2))
            if unit.isEmpty { guard lastUnit == "h" || lastUnit == "j" else { return nil }; unit = "m" }
            switch unit {
            case "h", "j": total += n * 3600
            case "m": total += n * 60
            default: total += n
            }
            lastUnit = unit
        }
        guard consumed == ns.length else { return nil }
        return total > 0 ? total : nil
    }
}
