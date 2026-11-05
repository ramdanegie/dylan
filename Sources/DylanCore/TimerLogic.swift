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

    public static func pomodoro(now: Date, config: PomodoroConfig = PomodoroConfig()) -> CountdownTimer {
        CountdownTimer(phase: .focus, duration: config.focus, endsAt: now.addingTimeInterval(config.focus), pausedRemaining: nil, focusCount: 0)
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
    /// A phase that does not start by itself (D58) comes back paused at its full length.
    public func next(now: Date, config: PomodoroConfig = PomodoroConfig()) -> CountdownTimer? {
        var n: CountdownTimer
        switch phase {
        case .timer:
            return nil
        case .focus:
            let count = focusCount + 1
            let long = count % config.sessionsBeforeLong == 0
            let d = long ? config.longBreak : config.shortBreak
            n = CountdownTimer(phase: long ? .longBreak : .shortBreak, duration: d,
                               endsAt: now.addingTimeInterval(d), pausedRemaining: nil, focusCount: count)
            if !config.autoBreak { n.pause(now: now) }
        case .shortBreak, .longBreak:
            n = CountdownTimer(phase: .focus, duration: config.focus, endsAt: now.addingTimeInterval(config.focus),
                               pausedRemaining: nil, focusCount: focusCount % config.sessionsBeforeLong)
            if !config.autoFocus { n.pause(now: now) }
        }
        return n
    }

    public var isBreak: Bool { phase == .shortBreak || phase == .longBreak }
}

/// Pomodoro lengths and what starts by itself (D58): breaks start automatically, the next focus does not.
public struct PomodoroConfig: Equatable, Sendable {
    public var focus: TimeInterval = CountdownTimer.focus
    public var shortBreak: TimeInterval = CountdownTimer.shortBreak
    public var longBreak: TimeInterval = CountdownTimer.longBreak
    public var sessionsBeforeLong = 4
    public var autoBreak = true
    public var autoFocus = false
    public init() {}
}

/// Stopwatch with laps (D58), on the wall clock so it keeps running while the Mac sleeps.
public struct Stopwatch: Equatable, Sendable {
    public var startedAt: Date?
    /// Time banked before the last pause.
    public var banked: TimeInterval = 0
    /// Lap end times as elapsed totals, oldest first.
    public var laps: [TimeInterval] = []

    public init() {}
    public static func started(now: Date) -> Stopwatch { var s = Stopwatch(); s.startedAt = now; return s }

    public var isRunning: Bool { startedAt != nil }
    public func elapsed(now: Date) -> TimeInterval { banked + (startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0) }

    public mutating func pause(now: Date) {
        guard let s = startedAt else { return }
        banked += max(0, now.timeIntervalSince(s)); startedAt = nil
    }
    public mutating func resume(now: Date) { if startedAt == nil { startedAt = now } }
    public mutating func lap(now: Date) { laps.append(elapsed(now: now)) }

    /// Each lap's own length, newest first (the list the notch shows).
    public var lapDurations: [TimeInterval] {
        zip(laps, [0] + laps).map { $0 - $1 }.reversed()
    }
}

/// Parses free timer input: `45m`, `1h30`, `1h 30m`, `90s`, `10` (minutes), `1:30` (m:ss).
public enum DurationParser {
    /// Timers longer than a day are rejected (and huge numbers can no longer overflow).
    public static let maxDuration: TimeInterval = 24 * 3600

    public static func parse(_ input: String) -> TimeInterval? {
        guard let t = parseUnbounded(input), t > 0, t <= maxDuration else { return nil }
        return t
    }

    private static func parseUnbounded(_ input: String) -> TimeInterval? {
        let s = input.lowercased().replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty, s.count <= 12 else { return nil }
        if let m = Int(s) { return TimeInterval(m) * 60 }
        if s.contains(":") {
            let p = s.split(separator: ":").compactMap { Int($0) }
            guard p.count == 2, p[1] < 60 else { return nil }
            return TimeInterval(p[0]) * 60 + TimeInterval(p[1])
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
        return total
    }
}
