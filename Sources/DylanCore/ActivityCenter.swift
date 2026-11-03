import Foundation

/// Decides which activities occupy the two Compact slots (Duo), what waits in the queue,
/// when results expire, and what lands in history. PRD §2.4 and FR-4/FR-5.
/// Pure value type: the app owns one and feeds it the clock, so every rule is unit-testable.
public struct ActivityCenter: Sendable {
    public struct Config: Sendable, Equatable {
        public var maxSlots = 2
        public var successHold: TimeInterval = 5
        public var failureHold: TimeInterval = 8
        public var historyLimit = 20
        public init() {}
    }

    public struct HistoryEntry: Equatable, Sendable {
        public var activity: Activity
        public var at: Date
    }

    public var config: Config
    public private(set) var activities: [String: Activity] = [:]
    public private(set) var history: [HistoryEntry] = []
    /// While the pointer rests on the notch the result timers stop (design M5).
    private var holdPausedSince: Date?

    public init(config: Config = Config()) { self.config = config }

    // MARK: Mutations

    /// Replaces the activity with the same id. Callers own `startedAt` (a new agent prompt restarts the clock).
    public mutating func upsert(_ activity: Activity) {
        var a = activity
        if !a.state.isResult { a.endedAt = nil }
        activities[a.id] = a
    }

    /// Turns a running activity into a P1 result that is shown briefly, then moved to history.
    public mutating func finish(_ id: String, success: Bool, value: String? = nil, detail: String? = nil, now: Date) {
        guard var a = activities[id] else { return }
        a.state = success ? .success : .failure
        a.priority = .p1
        a.symbol = success ? "checkmark" : "xmark"
        if let value { a.value = value }
        if let detail { a.detail = detail }
        a.progress = nil
        a.endedAt = now
        a.updatedAt = now
        activities[id] = a
    }

    /// Adds a one-shot result (e.g. `dylan notify`, "CI failed") that expires like any other result.
    public mutating func post(_ activity: Activity, now: Date) {
        var a = activity
        a.endedAt = now
        a.updatedAt = now
        if !a.state.isResult { a.state = .success }
        activities[a.id] = a
    }

    public mutating func remove(_ id: String, now: Date, toHistory: Bool = false) {
        guard let a = activities.removeValue(forKey: id) else { return }
        if toHistory { appendHistory(a, now: now) }
    }

    public mutating func setHoldPaused(_ paused: Bool, now: Date) {
        if paused {
            if holdPausedSince == nil { holdPausedSince = now }
            return
        }
        guard let since = holdPausedSince else { return }
        holdPausedSince = nil
        let pausedFor = now.timeIntervalSince(since)
        for (id, var a) in activities where a.endedAt != nil {
            a.endedAt = a.endedAt!.addingTimeInterval(pausedFor)
            activities[id] = a
        }
    }

    /// Expires results whose hold time is over. Returns the ids that were removed.
    @discardableResult
    public mutating func tick(now: Date) -> [String] {
        guard holdPausedSince == nil else { return [] }
        var expired: [String] = []
        for (id, a) in activities {
            guard let end = a.endedAt, a.priority != .p0 else { continue }
            let hold = a.state == .failure ? config.failureHold : config.successHold
            if now.timeIntervalSince(end) >= hold { expired.append(id) }
        }
        for id in expired.sorted() {
            let a = activities.removeValue(forKey: id)!
            appendHistory(a, now: now)
        }
        return expired
    }

    public mutating func clearHistory() { history.removeAll() }

    private mutating func appendHistory(_ a: Activity, now: Date) {
        // Ambient activities (music, charging) are not worth remembering.
        guard a.priority != .p3 else { return }
        history.insert(HistoryEntry(activity: a, at: a.endedAt ?? now), at: 0)
        if history.count > config.historyLimit { history.removeLast(history.count - config.historyLimit) }
    }

    // MARK: Queries

    /// All activities, most important first: priority, then most recently updated.
    public var ordered: [Activity] {
        activities.values.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    /// What the Compact ears show. In fullscreen only P0 survives (FR-5).
    public func slots(fullscreen: Bool = false) -> [Activity] {
        let candidates = ordered.filter { !fullscreen || $0.priority == .p0 }
        return Array(candidates.prefix(config.maxSlots))
    }

    public func queued(fullscreen: Bool = false) -> [Activity] {
        let shown = Set(slots(fullscreen: fullscreen).map(\.id))
        return ordered.filter { !shown.contains($0.id) }
    }

    public var urgentIDs: Set<String> { Set(activities.values.filter { $0.priority == .p0 }.map(\.id)) }
}
