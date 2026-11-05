import Foundation

/// Notifications that reached the island today (FR-110, design D57), grouped per conversation
/// (app + sender). Kept on this Mac only, 24 hours by default (or 7 days).
public struct NotificationHistory: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var app: String
        public var bundleID: String?
        public var title: String
        public var body: String
        public var at: Date
        /// Arrived while a Focus was on: counted, not shown (D57).
        public var held: Bool
        public init(id: String = UUID().uuidString, app: String, bundleID: String? = nil, title: String, body: String, at: Date, held: Bool = false) {
            self.id = id; self.app = app; self.bundleID = bundleID; self.title = title; self.body = body; self.at = at; self.held = held
        }
    }

    /// One conversation: the newest message on top and how many arrived.
    public struct Group: Equatable, Sendable, Identifiable {
        public var id: String
        public var latest: Entry
        public var count: Int
    }

    public static let maxEntries = 500
    public var entries: [Entry] = []
    public init() {}

    public mutating func add(_ e: Entry) {
        entries.insert(e, at: 0)
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
    }

    /// Drops what is older than `keep` seconds.
    public mutating func prune(now: Date, keep: TimeInterval) {
        entries.removeAll { now.timeIntervalSince($0.at) > keep }
    }

    public var groups: [Group] {
        var order: [String] = []
        var map: [String: Group] = [:]
        for e in entries {   // newest first
            let k = Self.key(e)
            if var g = map[k] { g.count += 1; map[k] = g } else { order.append(k); map[k] = Group(id: k, latest: e, count: 1) }
        }
        return order.compactMap { map[$0] }
    }

    public var heldCount: Int { entries.filter(\.held).count }

    /// Held messages are released (shown in the list as normal) when the Focus ends.
    public mutating func releaseHeld() { for i in entries.indices { entries[i].held = false } }

    static func key(_ e: Entry) -> String { e.app + "\u{1F}" + e.title }
}
