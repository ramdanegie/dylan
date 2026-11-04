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
        scanning = true
        result = nil
        items = []
        selected = []
        blocked = []
        refreshDisk()
        let developer = AppModel.shared.isDeveloper
        // Caches of running apps start unchecked (the app may be using them right now).
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
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
                    if Task.isCancelled { return }
                    await MainActor.run {
                    let p = StorageProvider.shared
                    let known = Set(p.items.map(\.id))
                    let found = found.filter { !known.contains($0.id) }   // a big old download is listed once
                    p.items += found
                    p.selected.formUnion(found.filter(\.selectedByDefault).map(\.id))
                    if denied { p.blocked.insert(c) }
                    p.scanned += 1
                    }
                }
            }
            await MainActor.run {
                let p = StorageProvider.shared
                // Same order every time: by category, biggest first.
                let order = Dictionary(uniqueKeysWithValues: StorageCategory.allCases.enumerated().map { ($1, $0) })
                p.items.sort { (order[$0.category]!, -$0.size) < (order[$1.category]!, -$1.size) }
                p.scanning = false
            }
        }
    }

    // MARK: Clean

    func clean() {
        let chosen = items.filter { selected.contains($0.id) }
        guard !chosen.isEmpty, !cleaning else { return }
        cleaning = true
        Task.detached(priority: .userInitiated) {
            let r = StorageCleaner(home: NSHomeDirectory()).clean(chosen)
            await MainActor.run {
                let p = StorageProvider.shared
                p.cleaning = false
                p.items.removeAll { r.done.contains($0.id) }
                p.selected.subtract(r.done)
                p.refreshDisk()
                var parts = [L("storage.freed", Self.bytes(r.freed))]
                if r.trashed > 0 { parts.append(L("storage.movedToTrash", r.trashed)) }
                if r.failed > 0 { parts.append(L("storage.failed", r.failed)) }
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
        case .appCaches: return children(of: url("Library/Caches"), c, min: 20 * StorageRules.mb, title: cacheTitle, runningCheck: true)
        case .logs: return children(of: url("Library/Logs"), c, min: 5 * StorageRules.mb)
        case .trash:
            let trash = url(".Trash")
            guard let kids = list(trash) else { return ([], fm.fileExists(atPath: trash.path)) }
            let size = kids.reduce(Int64(0)) { $0 + allocated($1) }
            // One row; cleaning empties it (each child is removed).
            // The .Trash folder itself is refused by isRemovable; the cleaner only empties it (see StorageCleaner).
            return (size > 0 ? [StorageItem(category: c, title: L("storage.emptyTrash"), path: trash.path, size: size,
                                            note: L("storage.items", kids.count))] : [], false)
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
            let running = runningCheck && StorageRules.bundleID(cacheFolder: u.lastPathComponent).map(self.running.contains) == true
            return item(c, u, size: size, title: title?(u), note: running ? L("storage.appRunning") : nil, running: running)
        }
        return (found, false)
    }

    /// Every scanned path goes through `isRemovable`; anything else is simply not offered.
    private func item(_ c: StorageCategory, _ u: URL, size: Int64, title: String? = nil, note: String? = nil, running: Bool = false) -> StorageItem? {
        guard StorageRules.isRemovable(u.path, home: home) else { return nil }
        return StorageItem(category: c, title: title ?? u.lastPathComponent, path: u.path, size: size, note: note, running: running)
    }

    /// Files over 1 GB in the folders people keep their own things in. Packages (Photos Library, apps, Final Cut
    /// libraries) are skipped whole: they are never offered as "a large file".
    private func largeFiles() -> ([StorageItem], Bool) {
        var out: [StorageItem] = []
        for rel in ["Desktop", "Documents", "Movies", "Downloads"] {
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
        return (Array(out.sorted { $0.size > $1.size }.prefix(50)), false)
    }

    /// node_modules not touched for 30 days, in project folders under the home folder (not Library or hidden).
    private func nodeModules() -> ([StorageItem], Bool) {
        var out: [StorageItem] = []
        let skipTop: Set<String> = ["Library", "Applications", "Movies", "Music", "Pictures", "Public"]
        guard let tops = list(URL(fileURLWithPath: home)) else { return ([], false) }
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        for top in tops where !top.lastPathComponent.hasPrefix(".") && !skipTop.contains(top.lastPathComponent) && !isSymlink(top) {
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
        return (out.filter { $0.size > 20 * StorageRules.mb }.sorted { $0.size > $1.size }, false)
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

    struct Result: Sendable { var done: Set<String> = []; var freed: Int64 = 0; var trashed = 0; var failed = 0 }

    func clean(_ items: [StorageItem]) -> Result {
        var r = Result()
        let fm = FileManager.default
        for i in items {
            let u = URL(fileURLWithPath: i.path)
            // Checked again right before removing: same rules as the scan, still there, not a symlink.
            let link = (try? u.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
            let isTrashRoot = i.category == .trash && i.path == (home as NSString).appendingPathComponent(".Trash")
            guard !link, fm.fileExists(atPath: i.path), isTrashRoot || StorageRules.isRemovable(i.path, home: home) else { r.failed += 1; continue }
            do {
                if isTrashRoot {
                    // Empty the Trash: its children, never the folder.
                    for kid in try fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: []) { try fm.removeItem(at: kid) }
                } else if i.category.action == .delete {
                    try fm.removeItem(at: u)
                } else {
                    try fm.trashItem(at: u, resultingItemURL: nil)
                }
                r.done.insert(i.id)
                // Items moved to the Trash only free space once the Trash is emptied.
                if i.category.action == .delete || isTrashRoot { r.freed += i.size } else { r.trashed += 1 }
            } catch {
                r.failed += 1
            }
        }
        return r
    }
}
