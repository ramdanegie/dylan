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
        // Low impact is deleted so the space comes back; emptying the Trash is the point of that row.
        case .appCaches, .logs, .xcodeDerivedData, .xcodeDeviceSupport, .simulatorCaches, .packageCaches, .trash: return .delete
        // Medium and high impact go to the Trash (PRD §F25), including node_modules.
        case .downloads, .largeFiles, .iosBackups, .dylanCaptures, .xcodeArchives, .nodeModules: return .trash
        }
    }

    /// Shown only in Developer Mode.
    public var isDeveloper: Bool {
        [.xcodeDerivedData, .xcodeArchives, .xcodeDeviceSupport, .simulatorCaches, .packageCaches, .nodeModules].contains(self)
    }

    /// The app that uses this category's files: it must not be running while they are removed.
    public var appID: String? {
        switch self {
        case .xcodeDerivedData, .xcodeArchives, .xcodeDeviceSupport: return "com.apple.dt.Xcode"
        case .simulatorCaches: return "com.apple.iphonesimulator"
        default: return nil
        }
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
    /// The app using these files (checked again right before cleaning). A trailing "." matches a bundle-id prefix.
    public var appID: String?
    /// May hold the user's own data although it sits in a cache folder (IDE local history, virtualenvs): never pre-checked.
    public var cautious: Bool
    /// Empty Trash only: the Trash's children seen by the scan (path → inode). Nothing else is removed.
    public var members: [String: UInt64]

    public init(category: StorageCategory, title: String, path: String, size: Int64, note: String? = nil, running: Bool = false,
                appID: String? = nil, cautious: Bool = false, members: [String: UInt64] = [:]) {
        self.category = category; self.title = title; self.path = path; self.size = size; self.note = note; self.running = running
        self.appID = appID; self.cautious = cautious; self.members = members
    }

    /// FR-102: only low-impact items start checked, never what a running app uses, never a cautious cache.
    public var selectedByDefault: Bool { category.impact == .low && !running && !cautious }
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
    /// Text rules only, compared case-insensitively (APFS usually is); the cleaner also requires the real path to equal
    /// this one, so a symlink anywhere in it is refused.
    public static func isRemovable(_ path: String, home: String) -> Bool {
        let p = (path as NSString).standardizingPath.lowercased(), h = (home as NSString).standardizingPath.lowercased()
        guard p.hasPrefix(h + "/"), !p.contains("/../") else { return false }
        let rel = String(p.dropFirst(h.count + 1))
        let parts = rel.split(separator: "/")
        guard let first = parts.first else { return false }
        if parts.count == 1 && (protectedTop.contains { $0.lowercased() == first } || first.hasPrefix(".")) { return false }
        // The category roots themselves (~/Library/Caches, ~/Library/Logs, …) stay.
        if parts.count == 2 && first == "library" { return false }
        // Media libraries are the user's photos and music, whatever their size.
        if parts.contains(where: { libraryExtensions.contains(($0 as NSString).pathExtension) }) { return false }
        return !neverInside.contains { n in
            let n = n.lowercased()
            return rel.hasPrefix(n) || rel == n.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
    }

    /// Cache folders that also keep user data: JetBrains/Android Studio Local History, Poetry virtualenvs.
    public static func isCautiousCache(_ relativeToCaches: String) -> Bool {
        let r = relativeToCaches.lowercased()
        return ["jetbrains", "androidstudio", "pypoetry", "localhistory"].contains { r.contains($0) }
    }

    /// Vendor folders in ~/Library/Caches that hold several apps; their children are listed one by one.
    public static let vendorCacheFolders: Set<String> = ["Google", "JetBrains"]

    /// The app behind a child of a vendor cache folder ("Google/Chrome", "Google/AndroidStudio2024.2", "JetBrains/IntelliJIdea2024.3").
    public static func vendorChildAppID(vendor: String, child: String) -> String? {
        switch vendor {
        case "Google": return child.hasPrefix("AndroidStudio") ? "com.google.android.studio" : child == "Chrome" ? "com.google.Chrome" : nil
        case "JetBrains": return "com.jetbrains."
        default: return nil
        }
    }

    /// Does `appID` (or the "com.jetbrains." prefix form) match a running app?
    public static func isRunning(_ appID: String?, in running: Set<String>) -> Bool {
        guard let appID else { return false }
        return appID.hasSuffix(".") ? running.contains { $0.hasPrefix(appID) } : running.contains(appID)
    }

    /// One row per path, and no row inside another row (the outer one already covers it). When two categories claim
    /// the same path, the one that moves it to the Trash wins.
    public static func normalize(_ items: [StorageItem]) -> [StorageItem] {
        var byPath: [String: StorageItem] = [:]
        for i in items {
            if let old = byPath[i.path], !(old.category.action == .delete && i.category.action == .trash) { continue }
            byPath[i.path] = i
        }
        let paths = byPath.keys.sorted()
        var kept: [StorageItem] = []
        var lastOuter: String?
        for p in paths {
            if let o = lastOuter, p.hasPrefix(o + "/") { continue }
            lastOuter = p
            kept.append(byPath[p]!)
        }
        return kept
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

    /// What "Clean" will do, said truthfully: deleted (rebuilds itself), Trash emptied (cannot be undone), moved to the
    /// Trash (frees nothing until the Trash is emptied).
    public struct Plan: Equatable, Sendable {
        public var count = 0, bytes: Int64 = 0
        public var deleted = 0, deletedBytes: Int64 = 0
        public var emptiesTrash = false, trashBytes: Int64 = 0
        public var trashed = 0, trashedBytes: Int64 = 0
        public init() {}
    }

    public static func plan(_ items: [StorageItem], selected: Set<String>) -> Plan {
        var p = Plan()
        for i in items where selected.contains(i.id) {
            p.count += 1; p.bytes += i.size
            if i.category == .trash { p.emptiesTrash = true; p.trashBytes += i.size }
            else if i.category.action == .delete { p.deleted += 1; p.deletedBytes += i.size }
            else { p.trashed += 1; p.trashedBytes += i.size }
        }
        return p
    }
}
