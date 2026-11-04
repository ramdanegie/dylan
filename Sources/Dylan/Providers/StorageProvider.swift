import AppKit
import DylanCore

/// Storage optimization (PRD §F25, FR-100–FR-103): a read-only scan of the home folder, a checklist, and a clean
/// that deletes only what rebuilds itself and moves everything else to the Trash.
@Observable
final class StorageProvider {
    static let shared = StorageProvider()

    var items: [StorageItem] = []
    var selected: Set<String> = []
    /// Categories macOS would not let Dylan read (Full Disk Access).
    var blocked: Set<StorageCategory> = []
    var scanning = false
    /// Categories finished / to scan (they run in parallel).
    var scanned = 0
    var toScan = 0
    var cleaning = false
    var result: String?
    var free: Int64 = 0
    var total: Int64 = 0

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var timer: Timer?

    var plan: StorageRules.Plan { StorageRules.plan(items, selected: selected) }

    // MARK: Disk

    func refreshDisk() {
        let v = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        free = v?.volumeAvailableCapacityForImportantUsage ?? 0
        total = Int64(v?.volumeTotalCapacity ?? 0)
    }

    // MARK: Low-space notice (FR-103)

    func start() {
        guard timer == nil else { return }
        checkSpace()
        let t = Timer(timeInterval: 30 * 60, repeats: true) { _ in MainActor.assumeIsolated { StorageProvider.shared.checkSpace() } }
        t.tolerance = 120
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func checkSpace() {
        refreshDisk()
        let d = AppModel.store
        guard d.object(forKey: "storage.warn") as? Bool ?? true, StorageRules.isLowSpace(free: free, total: total) else { return }
        // At most twice a day.
        if let last = d.object(forKey: "storage.warnedAt") as? Date, Date().timeIntervalSince(last) < 12 * 3600 { return }
        d.set(Date(), forKey: "storage.warnedAt")
        let now = Date()
        AppModel.shared.center.post(Activity(id: "storage-low", kind: .notify, priority: .p2, state: .needsAction, symbol: "internaldrive",
                                             label: L("storage.short"), value: Self.bytes(free),
                                             detail: L("storage.lowDetail", Self.bytes(free)), url: "storage:", startedAt: now), now: now)
        AppModel.shared.scheduleTick()
    }

    // MARK: Scan

    func scan() {
        scanTask?.cancel()
        scanGeneration += 1
        let generation = scanGeneration
        scanning = true
        result = nil
        items = []
        selected = []
        blocked = []
        refreshDisk()
        let developer = AppModel.shared.isDeveloper
        // What running apps use starts unchecked (and is checked again before cleaning).
        let running = Self.runningApps()
        let categories = StorageCategory.allCases.filter { developer || !$0.isDeveloper }
        let capturesDir = ScreenshotService.historyDir.path
        scanned = 0
        toScan = categories.count
        scanTask = Task.detached(priority: .utility) {
            let scanner = StorageScanner(home: NSHomeDirectory(), running: running, capturesDir: capturesDir)
            // In parallel: the slow walks (large files, caches, node_modules) overlap; results appear as they come.
            await withTaskGroup(of: (StorageCategory, [StorageItem], Bool).self) { group in
                for c in categories { group.addTask { let (f, d) = scanner.scan(c); return (c, f, d) } }
                for await (c, found, denied) in group {
                    await MainActor.run {
                        let p = StorageProvider.shared
                        guard p.scanGeneration == generation else { return }   // a newer scan started
                        p.items += found
                        if denied { p.blocked.insert(c) }
                        p.scanned += 1
                    }
                }
            }
            await MainActor.run {
                let p = StorageProvider.shared
                guard p.scanGeneration == generation else { return }
                // One row per path, nothing listed twice, nested rows dropped; then the default checks.
                let order = Dictionary(uniqueKeysWithValues: StorageCategory.allCases.enumerated().map { ($1, $0) })
                p.items = StorageRules.normalize(p.items).sorted { (order[$0.category]!, -$0.size) < (order[$1.category]!, -$1.size) }
                p.selected = Set(p.items.filter(\.selectedByDefault).map(\.id))
                p.scanning = false
            }
        }
    }

    /// Bundle ids of running apps (Xcode, Chrome, JetBrains IDEs…), read on the main thread.
    static func runningApps() -> Set<String> { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }

    // MARK: Clean

    func clean() {
        guard !cleaning, !scanning else { return }
        // Checked again now: an app may have started since the scan.
        let running = Self.runningApps()
        let chosen = items.filter { selected.contains($0.id) && !StorageRules.isRunning($0.appID, in: running) }
        let skipped = items.filter { selected.contains($0.id) }.count - chosen.count
        guard !chosen.isEmpty else { result = L("storage.skippedRunning", skipped); return }
        cleaning = true
        refreshDisk()
        let freeBefore = free
        let capturesDir = ScreenshotService.historyDir.path
        Task.detached(priority: .userInitiated) {
            let r = StorageCleaner(home: NSHomeDirectory()).clean(chosen)
            // Anything that went to the Trash changes the Trash row: list it again, so "Empty Trash" never removes
            // something the user has not seen.
            let trashRow = StorageScanner(home: NSHomeDirectory(), running: running, capturesDir: capturesDir).scan(.trash).0
            await MainActor.run {
                let p = StorageProvider.shared
                p.cleaning = false
                p.items.removeAll { r.done.contains($0.id) || $0.category == .trash }
                p.items.append(contentsOf: trashRow)
                p.selected.subtract(r.done)
                p.selected = p.selected.filter { id in p.items.contains { $0.id == id } }
                p.refreshDisk()
                let freed = max(0, p.free - freeBefore)
                // The change in free space, not a sum of sizes (hard links, clones and snapshots make that wrong).
                var parts = [L("storage.freed", Self.bytes(freed))]
                if r.trashed > 0 { parts.append(L("storage.movedToTrash", r.trashed)) }
                if r.failed > 0 { parts.append(L("storage.failed", r.failed)) }
                if skipped > 0 { parts.append(L("storage.skippedRunning", skipped)) }
                p.result = parts.joined(separator: " · ")
                AppModel.shared.center.remove("storage-low", now: Date())
            }
        }
    }

    nonisolated static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
}

// MARK: - Scanner (background, read-only)

/// Walks only the folders each category names, never follows symlinks, and keeps paths that pass
/// `StorageRules.isRemovable`. Sizes are what the files take on disk.
nonisolated struct StorageScanner: Sendable {
    let home: String
    let running: Set<String>
    let capturesDir: String
    private var fm: FileManager { .default }

    init(home: String, running: Set<String>, capturesDir: String) {
        self.home = home; self.running = running; self.capturesDir = capturesDir
    }

    private func url(_ rel: String) -> URL { URL(fileURLWithPath: home).appendingPathComponent(rel) }

    /// (items, true when macOS refused to list a folder that exists).
    func scan(_ c: StorageCategory) -> ([StorageItem], Bool) {
        switch c {
        case .appCaches: return appCaches()
        case .logs: return children(of: url("Library/Logs"), c, min: 5 * StorageRules.mb)
        case .trash:
            let trash = url(".Trash")
            guard let kids = list(trash) else { return ([], fm.fileExists(atPath: trash.path)) }
            let size = kids.reduce(Int64(0)) { $0 + allocated($1) }
            // One row. It remembers exactly what it saw (path → inode): emptying removes those and nothing added later.
            // The .Trash folder itself is refused by isRemovable; the cleaner only removes these members.
            var members: [String: UInt64] = [:]
            for k in kids { if let ino = Self.inode(k.path) { members[k.path] = ino } }
            return (size > 0 ? [StorageItem(category: c, title: L("storage.emptyTrash"), path: trash.path, size: size,
                                            note: L("storage.items", kids.count), members: members)] : [], false)
        case .downloads:
            let dl = url("Downloads")
            guard let kids = list(dl) else { return ([], fm.fileExists(atPath: dl.path)) }
            let now = Date()
            let found = kids.compactMap { u -> StorageItem? in
                let size = allocated(u), mod = modified(u)
                guard StorageRules.isStaleDownload(name: u.lastPathComponent, size: size, modified: mod, now: now) else { return nil }
                return item(c, u, size: size, note: L("storage.lastChanged", mod.formatted(date: .abbreviated, time: .omitted)))
            }
            return (found, false)
        case .largeFiles: return largeFiles()
        case .iosBackups:
            let root = url("Library/Application Support/MobileSync/Backup")
            guard let kids = list(root) else { return ([], fm.fileExists(atPath: root.path)) }
            return (kids.compactMap { u in
                let info = NSDictionary(contentsOf: u.appendingPathComponent("Info.plist"))
                let name = info?["Device Name"] as? String ?? u.lastPathComponent
                let date = (info?["Last Backup Date"] as? Date)?.formatted(date: .abbreviated, time: .omitted)
                return item(c, u, size: allocated(u), title: name, note: date.map { L("storage.backedUp", $0) })
            }, false)
        case .dylanCaptures:
            let u = URL(fileURLWithPath: capturesDir)
            let size = allocated(u)
            return (size > 0 ? [item(c, u, size: size, title: L("storage.cat.dylanCaptures"))].compactMap { $0 } : [], false)
        case .xcodeDerivedData: return children(of: url("Library/Developer/Xcode/DerivedData"), c, min: 20 * StorageRules.mb, title: derivedTitle)
        case .xcodeArchives: return children(of: url("Library/Developer/Xcode/Archives"), c, min: StorageRules.mb)
        case .xcodeDeviceSupport:
            let a = children(of: url("Library/Developer/Xcode/iOS DeviceSupport"), c, min: 50 * StorageRules.mb)
            let b = children(of: url("Library/Developer/Xcode/watchOS DeviceSupport"), c, min: 50 * StorageRules.mb)
            return (a.0 + b.0, a.1 || b.1)
        case .simulatorCaches:
            let u = url("Library/Developer/CoreSimulator/Caches")
            let size = allocated(u)
            return (size > 20 * StorageRules.mb ? [item(c, u, size: size, title: L("storage.simulatorCaches"))].compactMap { $0 } : [], false)
        case .packageCaches:
            let found = [(".npm/_cacache", "npm"), (".gradle/caches", "Gradle"), ("Library/pnpm/store", "pnpm"), (".cache/yarn", "Yarn"),
                         (".cargo/registry/cache", "Cargo")].compactMap { rel, name -> StorageItem? in
                let u = url(rel), size = allocated(u)
                return size > 20 * StorageRules.mb ? item(c, u, size: size, title: name) : nil
            }
            return (found, false)
        case .nodeModules: return nodeModules()
        }
    }

    // MARK: Walkers

    private func list(_ dir: URL) -> [URL]? {
        try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [])
    }

    private func children(of dir: URL, _ c: StorageCategory, min: Int64, title: ((URL) -> String)? = nil,
                          runningCheck: Bool = false) -> ([StorageItem], Bool) {
        guard let kids = list(dir) else { return ([], fm.fileExists(atPath: dir.path)) }
        let found = kids.compactMap { u -> StorageItem? in
            guard !isSymlink(u) else { return nil }
            let size = allocated(u)
            guard size >= min else { return nil }
            let app = runningCheck ? StorageRules.bundleID(cacheFolder: u.lastPathComponent) : c.appID
            let running = StorageRules.isRunning(app, in: self.running)
            return item(c, u, size: size, title: title?(u), note: running ? L("storage.appRunning") : nil, running: running, appID: app)
        }
        return (found, false)
    }

    /// Every scanned path goes through `isRemovable`; anything else is simply not offered.
    private func item(_ c: StorageCategory, _ u: URL, size: Int64, title: String? = nil, note: String? = nil, running: Bool = false,
                      appID: String? = nil, cautious: Bool = false) -> StorageItem? {
        guard StorageRules.isRemovable(u.path, home: home) else { return nil }
        let app = appID ?? c.appID
        let isRunning = running || StorageRules.isRunning(app, in: self.running)
        return StorageItem(category: c, title: title ?? u.lastPathComponent, path: u.path, size: size,
                           note: note ?? (isRunning ? L("storage.appRunning") : nil), running: isRunning, appID: app, cautious: cautious)
    }

    /// ~/Library/Caches, one row per app. Vendor folders (Google, JetBrains) are listed per app inside them, and caches that
    /// also keep user data (IDE local history, Poetry virtualenvs) are marked cautious: never pre-checked.
    private func appCaches() -> ([StorageItem], Bool) {
        let root = url("Library/Caches")
        guard let kids = list(root) else { return ([], fm.fileExists(atPath: root.path)) }
        var out: [StorageItem] = []
        for u in kids where !isSymlink(u) {
            let name = u.lastPathComponent
            if StorageRules.vendorCacheFolders.contains(name), let inner = list(u) {
                for v in inner where !isSymlink(v) {
                    let size = allocated(v)
                    guard size >= 20 * StorageRules.mb else { continue }
                    let rel = name + "/" + v.lastPathComponent
                    let cautious = StorageRules.isCautiousCache(rel)
                    if let i = item(.appCaches, v, size: size, title: vendorTitle(name, v.lastPathComponent),
                                    note: cautious ? L("storage.cautious") : nil,
                                    appID: StorageRules.vendorChildAppID(vendor: name, child: v.lastPathComponent), cautious: cautious) { out.append(i) }
                }
                continue
            }
            let size = allocated(u)
            guard size >= 20 * StorageRules.mb else { continue }
            let cautious = StorageRules.isCautiousCache(name)
            if let i = item(.appCaches, u, size: size, title: cacheTitle(u), note: cautious ? L("storage.cautious") : nil,
                            appID: StorageRules.bundleID(cacheFolder: name), cautious: cautious) { out.append(i) }
        }
        return (out, false)
    }

    private func vendorTitle(_ vendor: String, _ child: String) -> String {
        if vendor == "Google" && child == "Chrome" { return "Google Chrome" }
        return vendor == "JetBrains" ? "JetBrains " + child : child
    }

    static func inode(_ path: String) -> UInt64? {
        var st = stat()
        return lstat(path, &st) == 0 ? UInt64(st.st_ino) : nil
    }

    /// Files over 1 GB in the folders people keep their own things in. Packages (Photos Library, apps, Final Cut
    /// libraries) are skipped whole: they are never offered as "a large file".
    private func largeFiles() -> ([StorageItem], Bool) {
        var out: [StorageItem] = []
        var denied = false
        for rel in ["Desktop", "Documents", "Movies", "Downloads"] {
            // A folder macOS will not let Dylan read must not look like "nothing to clean".
            if fm.fileExists(atPath: url(rel).path), list(url(rel)) == nil { denied = true; continue }
            guard let e = fm.enumerator(at: url(rel), includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey, .isPackageKey],
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let u as URL in e {
                let v = try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey, .isPackageKey])
                if v?.isPackage == true || StorageRules.dependencyFolders.contains(u.lastPathComponent) { e.skipDescendants(); continue }
                guard v?.isRegularFile == true, let s = v?.totalFileAllocatedSize, Int64(s) >= StorageRules.gb,
                      let i = item(.largeFiles, u, size: Int64(s)) else { continue }
                out.append(i)
            }
        }
        return (Array(out.sorted { $0.size > $1.size }.prefix(50)), denied)
    }

    /// node_modules not touched for 30 days, in project folders under the home folder (not Library or hidden).
    private func nodeModules() -> ([StorageItem], Bool) {
        var out: [StorageItem] = []
        var denied = false
        let skipTop: Set<String> = ["Library", "Applications", "Movies", "Music", "Pictures", "Public"]
        guard let tops = list(URL(fileURLWithPath: home)) else { return ([], false) }
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        for top in tops where !top.lastPathComponent.hasPrefix(".") && !skipTop.contains(top.lastPathComponent) && !isSymlink(top) {
            if list(top) == nil { if (try? top.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { denied = true }; continue }
            guard let e = fm.enumerator(at: top, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let u as URL in e {
                if e.level > 6 { e.skipDescendants(); continue }
                guard u.lastPathComponent == "node_modules" else { continue }
                e.skipDescendants()
                guard modified(u) < cutoff else { continue }
                let project = u.deletingLastPathComponent().lastPathComponent
                if let i = item(.nodeModules, u, size: allocated(u), title: project) { out.append(i) }
            }
        }
        return (out.filter { $0.size > 20 * StorageRules.mb }.sorted { $0.size > $1.size }, denied)
    }

    // MARK: Sizes

    private func isSymlink(_ u: URL) -> Bool { (try? u.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true }

    private func modified(_ u: URL) -> Date {
        (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
    }

    /// Bytes on disk, recursively; symlinks count as themselves and are not followed.
    func allocated(_ u: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let v = try? u.resourceValues(forKeys: Set(keys)) else { return 0 }
        if v.isSymbolicLink == true || v.isDirectory != true { return Int64(v.totalFileAllocatedSize ?? 0) }
        guard let e = fm.enumerator(at: u, includingPropertiesForKeys: keys, options: []) else { return 0 }
        var sum: Int64 = 0
        for case let f as URL in e {
            sum += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return sum
    }

    private func cacheTitle(_ u: URL) -> String {
        let name = u.lastPathComponent
        guard let id = StorageRules.bundleID(cacheFolder: name), let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return name }
        return FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    /// "MyApp-abcdefgh" → "MyApp".
    private func derivedTitle(_ u: URL) -> String {
        let n = u.lastPathComponent
        return n.range(of: "-", options: .backwards).map { String(n[..<$0.lowerBound]) } ?? n
    }
}

// MARK: - Cleaner (background)

nonisolated struct StorageCleaner: Sendable {
    let home: String

    struct Result: Sendable { var done: Set<String> = []; var trashed = 0; var failed = 0 }

    /// The real path must be the path we were given: a symlink anywhere in it, or a case or firmlink mismatch, refuses.
    private func isExact(_ path: String) -> Bool {
        guard let real = realpath(path, nil) else { return false }
        defer { free(real) }
        // Compared as given: standardizingPath would turn /private/tmp into /tmp and refuse every real path there.
        return String(cString: real) == path
    }

    func clean(_ items: [StorageItem]) -> Result {
        var r = Result()
        let fm = FileManager.default
        let trashRoot = (home as NSString).appendingPathComponent(".Trash")
        for i in items {
            let u = URL(fileURLWithPath: i.path)
            if i.category == .trash {
                // Empty Trash: only the members the scan listed, each still the same file (inode); one locked file does
                // not stop the rest.
                guard i.path == trashRoot, isExact(trashRoot) else { r.failed += 1; continue }
                var ok = true
                for (path, ino) in i.members {
                    guard (path as NSString).deletingLastPathComponent == trashRoot, StorageScanner.inode(path) == ino else { continue }
                    do { try fm.removeItem(atPath: path) } catch { ok = false; r.failed += 1 }
                }
                if ok { r.done.insert(i.id) }
                continue
            }
            // Checked again right before removing: same rules as the scan, still there, no symlink in the path.
            guard fm.fileExists(atPath: i.path), isExact(i.path), StorageRules.isRemovable(i.path, home: home) else { r.failed += 1; continue }
            do {
                if i.category.action == .delete { try fm.removeItem(at: u) } else { try fm.trashItem(at: u, resultingItemURL: nil); r.trashed += 1 }
                r.done.insert(i.id)
            } catch {
                r.failed += 1
            }
        }
        return r
    }
}
