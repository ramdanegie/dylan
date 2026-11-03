import Foundation

/// "Time to leave" (FR-81): for today's events at a physical place, leave at start − travel − buffer.
public enum TimeToLeave {
    public static let buffer: TimeInterval = 5 * 60
    /// Only events this close get a travel estimate (one request each, refreshed every 10 minutes).
    public static let lookahead: TimeInterval = 3 * 3600

    /// The event's location when it is somewhere to go, not a video link or a room-less "Online".
    public static func physicalPlace(_ location: String?) -> String? {
        guard let s = location?.trimmingCharacters(in: .whitespacesAndNewlines), s.count >= 3 else { return nil }
        // A web address with or without a scheme ("meet.google.com/abc-defg-hij") is not a place.
        if s.contains("://") || MeetingLink.find(in: [s]) != nil || s.range(of: #"^\S+\.\S+/\S*$"#, options: .regularExpression) != nil { return nil }
        let lower = s.lowercased()
        if ["online", "daring", "virtual", "remote", "zoom", "google meet", "microsoft teams", "teams", "meet"].contains(lower) { return nil }
        return s
    }

    public static func candidates(_ events: [MeetingSchedule.Event], now: Date) -> [MeetingSchedule.Event] {
        events.filter { !$0.isAllDay && $0.place != nil && $0.start > now && $0.start.timeIntervalSince(now) <= lookahead }
            .sorted { $0.start < $1.start }
    }

    public static func leaveAt(start: Date, travel: TimeInterval) -> Date { start.addingTimeInterval(-travel - buffer) }

    /// Alert once, from the leave time until the event starts.
    public static func shouldAlert(now: Date, start: Date, travel: TimeInterval, alreadyAlerted: Bool) -> Bool {
        !alreadyAlerted && now >= leaveAt(start: start, travel: travel) && now < start
    }
}
