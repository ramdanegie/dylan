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

    /// `dir/name.ext`, or `dir/name 2.ext`, `name 3.ext`… so a result never replaces an existing file.
    public static func freePath(dir: String, name: String, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var path = (dir as NSString).appendingPathComponent(name), n = 2
        while exists(path) {
            path = (dir as NSString).appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return path
    }

    /// Name for a zip of several items: `Shelf 2026-11-04 09.41.zip`, or `<name>.zip` for one.
    public static func zipName(for items: [Item], now: Date) -> String {
        if items.count == 1 { return ((items[0].name as NSString).deletingPathExtension) + ".zip" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return "Shelf \(f.string(from: now)).zip"
    }
}

/// "Shake while dragging" for the floating basket (FR-86): ≥ 3 direction changes of ≥ 30 pt within 0.6 s.
public struct ShakeDetector: Sendable {
    public var window: TimeInterval = 0.6
    public var minTravel: CGFloat = 30
    public var reversals = 3
    private var samples: [(x: CGFloat, t: TimeInterval)] = []
    public init() {}

    public mutating func reset() { samples.removeAll() }

    /// Feed pointer x positions while a file drag is in progress; true once a shake is seen.
    public mutating func feed(x: CGFloat, time: TimeInterval) -> Bool {
        samples.append((x, time))
        samples.removeAll { time - $0.t > window }
        var turns = 0
        var direction: CGFloat = 0
        var anchor = samples.first?.x ?? x
        for s in samples.dropFirst() {
            let d = s.x - anchor
            guard abs(d) >= minTravel else { continue }
            let dir: CGFloat = d > 0 ? 1 : -1
            if direction != 0 && dir != direction { turns += 1 }
            direction = dir
            anchor = s.x
        }
        if turns >= reversals { samples.removeAll(); return true }
        return false
    }
}
