import Foundation

/// Storage optimization (PRD §F25, FR-100–FR-103). Pure rules; the app scans and deletes.
public enum StorageImpact: Int, Comparable, Sendable, CaseIterable {
    /// Rebuilt automatically (caches, logs, builds).
    case low
    /// Needs a download or rebuild, or cannot be restored but is not the user's own work (Trash, archives).
    case medium
    /// The user's own data (downloads, large files, iPhone backups).
    case high
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// What "Clean" does with an item.
public enum StorageAction: Sendable {
    /// Gone for good: only for things that rebuild themselves, so the space really comes back.
    case delete
    /// Moved to the Trash, so it can still be put back.
    case trash
}

public enum StorageCategory: String, CaseIterable, Sendable {
    case appCaches, logs, trash, downloads, largeFiles, iosBackups, dylanCaptures
    case xcodeDerivedData, xcodeArchives, xcodeDeviceSupport, simulatorCaches, packageCaches, nodeModules

    public var impact: StorageImpact {
        switch self {
        case .appCaches, .logs, .xcodeDerivedData, .xcodeDeviceSupport, .simulatorCaches, .packageCaches: return .low
        case .trash, .xcodeArchives, .nodeModules, .dylanCaptures: return .medium
        case .downloads, .largeFiles, .iosBackups: return .high
        }
    }

    public var action: StorageAction {
        switch self {
        // Emptying the Trash is the point; node_modules is rebuilt by `npm install`.
        case .appCaches, .logs, .xcodeDerivedData, .xcodeDeviceSupport, .simulatorCaches, .packageCaches, .trash, .nodeModules: return .delete
        case .downloads, .largeFiles, .iosBackups, .dylanCaptures, .xcodeArchives: return .trash
        }
    }

    /// Shown only in Developer Mode.
    public var isDeveloper: Bool {
        [.xcodeDerivedData, .xcodeArchives, .xcodeDeviceSupport, .simulatorCaches, .packageCaches, .nodeModules].contains(self)
    }
}

public struct StorageItem: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let category: StorageCategory
    public let title: String
    public let path: String
    public let size: Int64
    /// e.g. "the app is running" — such items start unchecked.
    public var note: String?
    public var running: Bool

    public init(category: StorageCategory, title: String, path: String, size: Int64, note: String? = nil, running: Bool = false) {
        self.category = category; self.title = title; self.path = path; self.size = size; self.note = note; self.running = running
    }

    /// FR-102: only low-impact items start checked, and never the cache of an app that is running.
    public var selectedByDefault: Bool { category.impact == .low && !running }
}

public enum StorageRules {
    public static let gb: Int64 = 1_000_000_000
    public static let mb: Int64 = 1_000_000

    /// Top-level folders of the home folder that are never removed themselves (their contents may be).
    public static let protectedTop: Set<String> = ["Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures",
                                                    "Public", "Applications", ".Trash", ".ssh", ".config"]
    /// Places whose deletion would sync to the cloud or break the system: never inside these.
    public static let neverInside = ["Library/Mobile Documents", "Library/CloudStorage", "Library/Keychains", "Library/Containers/com.apple.",
                                     "Library/Group Containers", "Library/Application Support/AddressBook", "Library/Messages", "Library/Mail/"]

    public static let libraryExtensions: Set<String> = ["photoslibrary", "photolibrary", "musiclibrary", "tvlibrary", "aplibrary", "fcpbundle", "logicx"]

    /// The last check before anything is removed (also run on scanned paths): strictly inside the home folder,
    /// at least two levels down unless it is a non-protected top-level item, and outside the places above.
    public static func isRemovable(_ path: String, home: String) -> Bool {
        let p = (path as NSString).standardizingPath, h = (home as NSString).standardizingPath
        guard p.hasPrefix(h + "/"), !p.contains("/../") else { return false }
        let rel = String(p.dropFirst(h.count + 1))
        let parts = rel.split(separator: "/")
        guard let first = parts.first else { return false }
        if parts.count == 1 && (protectedTop.contains(String(first)) || first.hasPrefix(".")) { return false }
        // The category roots themselves (~/Library/Caches, ~/Library/Logs, …) stay.
        if parts.count == 2 && first == "Library" { return false }
        // Media libraries are the user's photos and music, whatever their size.
        if parts.contains(where: { libraryExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) { return false }
        return !neverInside.contains { rel.hasPrefix($0) || rel == $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    }

    /// Downloads worth showing: big and untouched for a month, or an installer left over for a week.
    public static func isStaleDownload(name: String, size: Int64, modified: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(modified)
        let installer = ["dmg", "pkg", "xip", "iso"].contains((name as NSString).pathExtension.lowercased())
        if installer { return size >= 20 * mb && age >= 7 * 86_400 }
        return size >= 100 * mb && age >= 30 * 86_400
    }

    /// FR-103: warn under 10 GB free, or under 10 % of the disk.
    public static func isLowSpace(free: Int64, total: Int64) -> Bool {
        guard total > 0 else { return false }
        return free < 10 * gb || Double(free) / Double(total) < 0.10
    }

    /// Cache folders named after the vendor rather than the bundle id (Chrome keeps its cache in "Google").
    public static let knownCacheApps: [String: String] = [
        "Google": "com.google.Chrome", "Mozilla": "org.mozilla.firefox", "Firefox": "org.mozilla.firefox",
        "BraveSoftware": "com.brave.Browser", "Microsoft Edge": "com.microsoft.edgemac", "Arc": "company.thebrowser.Browser",
        "Vivaldi": "com.vivaldi.Vivaldi", "Opera": "com.operasoftware.Opera", "Slack": "com.tinyspeck.slackmacgap",
        "Spotify": "com.spotify.client", "Discord": "com.hnc.Discord", "zoom.us": "us.zoom.xos",
    ]

    /// Folders that hold rebuilt dependencies or build output, not the user's own files: the large-file scan skips them.
    public static let dependencyFolders: Set<String> = ["node_modules", "Pods", "vendor", "site-packages", "__pycache__", "target",
                                                        "build", "DerivedData", "bower_components", "Carthage"]

    /// "com.apple.Safari" → a bundle id; "Google" → Chrome's; "Homebrew", "pip" → nil.
    public static func bundleID(cacheFolder name: String) -> String? {
        if let known = knownCacheApps[name] { return known }
        let parts = name.split(separator: ".")
        return parts.count >= 2 && parts.allSatisfy({ !$0.isEmpty }) && !name.hasSuffix(".noindex") ? name : nil
    }

    public struct Plan: Equatable, Sendable {
        public var count = 0, bytes: Int64 = 0, deleted = 0, trashed = 0
    }

    public static func plan(_ items: [StorageItem], selected: Set<String>) -> Plan {
        var p = Plan()
        for i in items where selected.contains(i.id) {
            p.count += 1; p.bytes += i.size
            if i.category.action == .delete { p.deleted += 1 } else { p.trashed += 1 }
        }
        return p
    }
}
