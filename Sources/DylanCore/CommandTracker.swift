import Foundation

/// Tracks shell commands reported by the zsh integration. PRD §F4.
/// One running command per shell (keyed by shell PID).
public struct CommandTracker: Sendable {
    public struct Running: Equatable, Sendable {
        public var shellPid: Int
        public var command: String
        public var cwd: String
        public var app: String?
        public var startedAt: Date
        public var seq: Int?
    }

    public struct Finished: Equatable, Sendable {
        public var running: Running
        public var status: Int
        public var duration: TimeInterval
    }

    public var filter: CommandFilter
    public private(set) var running: [Int: Running] = [:]
    /// Highest command number already ended per shell; a `start` at or below it arrived late.
    private var lastEnded: [Int: Int] = [:]

    public init(filter: CommandFilter = CommandFilter()) { self.filter = filter }

    public mutating func start(shellPid: Int, command: String, cwd: String, app: String?, seq: Int? = nil, now: Date) {
        if let seq, let ended = lastEnded[shellPid], seq <= ended { return }
        guard !filter.isIgnored(command) else { running[shellPid] = nil; return }
        running[shellPid] = Running(shellPid: shellPid, command: TextRules.truncateTail(TextRules.singleLine(command), max: 200),
                                    cwd: cwd, app: app, startedAt: now, seq: seq)
    }

    /// Commands that have run past the threshold and should be visible now.
    public func visible(now: Date) -> [Running] {
        running.values.filter { filter.shouldShowRunning(elapsed: now.timeIntervalSince($0.startedAt)) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    /// Ends the shell's command. Returns the result only when it ran long enough to be worth showing.
    public mutating func end(shellPid: Int, status: Int, seq: Int? = nil, now: Date) -> Finished? {
        if let seq {
            lastEnded[shellPid] = max(lastEnded[shellPid] ?? 0, seq)
            // An end for an older or not-yet-started command must not close the current one.
            guard let r = running[shellPid], r.seq == nil || r.seq == seq else { return nil }
        }
        guard let r = running.removeValue(forKey: shellPid) else { return nil }
        let d = now.timeIntervalSince(r.startedAt)
        guard d >= filter.threshold else { return nil }
        return Finished(running: r, status: status, duration: d)
    }

    /// The shell went away without an `end` (closed tab): forget it silently.
    public mutating func forget(shellPid: Int) { running[shellPid] = nil; lastEnded[shellPid] = nil }
}
