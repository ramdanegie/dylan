import Foundation

/// Picks the meeting to show and how urgent it is. PRD §F6 / FR-12.
public enum MeetingSchedule {
    public struct Event: Equatable, Sendable {
        public var id: String
        public var title: String
        public var start: Date
        public var end: Date
        public var link: MeetingLink?
        public var isAllDay: Bool
        /// A physical place (not a meeting link), for "time to leave" (FR-81).
        public var place: String?
        public var coordinate: Coordinate?
        public init(id: String, title: String, start: Date, end: Date, link: MeetingLink?, isAllDay: Bool = false,
                    place: String? = nil, coordinate: Coordinate? = nil) {
            self.id = id; self.title = title; self.start = start; self.end = end; self.link = link; self.isAllDay = isAllDay
            self.place = place; self.coordinate = coordinate
        }
    }

    public struct Coordinate: Equatable, Sendable {
        public var latitude: Double, longitude: Double
        public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
    }

    public enum Phase: Equatable, Sendable {
        /// 10 minutes or less before start: P1.
        case soon
        /// 1 minute or less before start, until 5 minutes after: P0 with Join.
        case imminent
    }

    public static let soonWindow: TimeInterval = 10 * 60
    public static let imminentWindow: TimeInterval = 60
    /// Keep the Join card a little after start, for people who are late.
    public static let graceAfterStart: TimeInterval = 5 * 60

    /// The next relevant timed event and its phase, or nil when nothing starts within 10 minutes.
    public static func current(_ events: [Event], now: Date, dismissed: Set<String> = []) -> (Event, Phase)? {
        let candidates = events
            .filter { !$0.isAllDay && !dismissed.contains($0.id) }
            .filter { $0.start.timeIntervalSince(now) <= soonWindow && now.timeIntervalSince($0.start) <= graceAfterStart && now < $0.end }
            .sorted { $0.start < $1.start }
        guard let e = candidates.first else { return nil }
        return (e, e.start.timeIntervalSince(now) <= imminentWindow ? .imminent : .soon)
    }

    /// The next moment the phase can change, so the app can schedule one timer instead of polling.
    public static func nextChange(_ events: [Event], now: Date) -> Date? {
        events.filter { !$0.isAllDay }
            .flatMap { [$0.start.addingTimeInterval(-soonWindow), $0.start.addingTimeInterval(-imminentWindow),
                        $0.start.addingTimeInterval(graceAfterStart), $0.end] }
            .filter { $0 > now }
            .min()
    }
}
