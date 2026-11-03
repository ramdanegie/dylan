import Foundation

/// PRD §2.4. Lower raw value = more urgent.
public enum Priority: Int, Codable, Comparable, Sendable {
    case p0 = 0, p1 = 1, p2 = 2, p3 = 3
    public static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
}

public enum ActivityKind: String, Codable, Sendable {
    case agent, command, script, notify, media, meeting, timer, battery, bluetooth, port, ci, presentation, discord, focus
}

public enum ActivityState: Equatable, Codable, Sendable {
    case running
    case needsAction
    case info
    case success
    case failure
    case ambient

    public var isResult: Bool { self == .success || self == .failure }
}

/// One thing the notch can show. Providers build these; ActivityCenter decides what is visible.
public struct Activity: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var kind: ActivityKind
    public var priority: Priority
    public var state: ActivityState
    /// SF Symbol for the left ear.
    public var symbol: String
    /// Short label for the left ear (≤ ~8 chars in Compact).
    public var label: String
    /// Short value for the right ear (duration, countdown, percent). Never truncated.
    public var value: String
    /// One-line detail for Peek.
    public var detail: String
    /// Replacement text while Presentation Mode is on (PRD §F12). nil = activity has nothing sensitive.
    public var genericDetail: String?
    public var progress: Double?
    public var url: String?
    public var startedAt: Date
    public var updatedAt: Date
    /// Set when the activity turns into a result; used for the 5 s / 8 s hold.
    public var endedAt: Date?

    public init(
        id: String, kind: ActivityKind, priority: Priority, state: ActivityState,
        symbol: String, label: String, value: String = "", detail: String = "",
        genericDetail: String? = nil, progress: Double? = nil, url: String? = nil,
        startedAt: Date, updatedAt: Date? = nil, endedAt: Date? = nil
    ) {
        self.id = id; self.kind = kind; self.priority = priority; self.state = state
        self.symbol = symbol; self.label = label; self.value = value; self.detail = detail
        self.genericDetail = genericDetail; self.progress = progress; self.url = url
        self.startedAt = startedAt; self.updatedAt = updatedAt ?? startedAt; self.endedAt = endedAt
    }
}
