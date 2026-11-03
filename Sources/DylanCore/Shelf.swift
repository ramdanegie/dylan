import Foundation

/// File shelf (FR-23/24, PRD §F9). Files are referenced, never copied; moved or deleted files are flagged.
public struct Shelf: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var path: String
        public var addedAt: Date
        public var fromScreenshot: Bool
        public init(id: UUID = UUID(), path: String, addedAt: Date, fromScreenshot: Bool = false) {
            self.id = id; self.path = path; self.addedAt = addedAt; self.fromScreenshot = fromScreenshot
        }
        public var name: String { (path as NSString).lastPathComponent }
        public var ext: String { (path as NSString).pathExtension.uppercased() }
    }

    public private(set) var items: [Item] = []
    public var limit = 50
    public init() {}

    /// Adds paths (newest first); a path already on the shelf moves to the front.
    public mutating func add(_ paths: [String], now: Date, fromScreenshot: Bool = false) {
        for p in paths.reversed() {
            let std = (p as NSString).standardizingPath
            items.removeAll { $0.path == std }
            items.insert(Item(path: std, addedAt: now, fromScreenshot: fromScreenshot), at: 0)
        }
        if items.count > limit { items.removeLast(items.count - limit) }
    }

    public mutating func remove(_ id: UUID) { items.removeAll { $0.id == id } }
    public mutating func clear() { items.removeAll() }

    /// Paths that no longer exist ("dipindah" in the design).
    public func missing(exists: (String) -> Bool) -> Set<UUID> { Set(items.filter { !exists($0.path) }.map(\.id)) }

    /// Name for a zip of several items: `Shelf 2026-11-04 09.41.zip`, or `<name>.zip` for one.
    public static func zipName(for items: [Item], now: Date) -> String {
        if items.count == 1 { return ((items[0].name as NSString).deletingPathExtension) + ".zip" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return "Shelf \(f.string(from: now)).zip"
    }
}
