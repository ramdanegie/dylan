import AppKit
import DylanCore
import QuickLookThumbnailing

/// File shelf (FR-23/24, PRD §F9). References only; new screenshots arrive through Spotlight
/// (kMDItemIsScreenCapture), so there is no folder polling.
@Observable
final class ShelfProvider {
    static let shared = ShelfProvider()

    private(set) var shelf = Shelf()
    var thumbnails: [UUID: NSImage] = [:]
    var missing: Set<UUID> = []
    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var started = Date()

    static var fileURL: URL { Bridge.socketURL.deletingLastPathComponent().appendingPathComponent("shelf.json") }

    func start() {
        if let d = try? Data(contentsOf: Self.fileURL), let s = try? JSONDecoder().decode(Shelf.self, from: d) { shelf = s }
        refreshMissing()
        startScreenshotWatch()
    }

    func stop() {
        query?.stop(); query = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func add(_ urls: [URL], fromScreenshot: Bool = false) {
        let paths = urls.filter(\.isFileURL).map(\.path)
        guard !paths.isEmpty else { return }
        shelf.add(paths, now: Date(), fromScreenshot: fromScreenshot)
        save()
        refreshMissing()
        loadThumbnails()
    }

    func remove(_ id: UUID) { shelf.remove(id); thumbnails[id] = nil; save() }
    func clear() { shelf.clear(); thumbnails = [:]; save() }

    func url(_ item: Shelf.Item) -> URL { URL(fileURLWithPath: item.path) }

    // MARK: Actions

    func quickLook(_ item: Shelf.Item) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        p.arguments = ["-p", item.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    func copyPath(_ item: Shelf.Item) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.path, forType: .string)
    }

    /// Opens in VS Code or Zed when installed, otherwise the default app.
    func openInEditor(_ item: Shelf.Item) {
        let ws = NSWorkspace.shared
        let editor = ["com.microsoft.VSCode", "dev.zed.Zed"].lazy.compactMap { ws.urlForApplication(withBundleIdentifier: $0) }.first
        if let editor { ws.open([url(item)], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration()) } else { ws.open(url(item)) }
    }

    func reveal(_ item: Shelf.Item) { NSWorkspace.shared.activateFileViewerSelecting([url(item)]) }

    func airDrop(_ items: [Shelf.Item]) {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: items.map(url))
    }

    /// Zips next to the first item with `ditto` and puts the archive on the shelf.
    func zip(_ items: [Shelf.Item]) {
        guard let first = items.first else { return }
        let dest = URL(fileURLWithPath: (first.path as NSString).deletingLastPathComponent)
            .appendingPathComponent(Shelf.zipName(for: items, now: Date()))
        let paths = items.map(\.path)
        Task.detached {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            for p in paths { try? FileManager.default.copyItem(atPath: p, toPath: tmp.appendingPathComponent((p as NSString).lastPathComponent).path) }
            let ok = Shell.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", tmp.path, dest.path], timeout: 120) != nil
            try? FileManager.default.removeItem(at: tmp)
            await MainActor.run { if ok { ShelfProvider.shared.add([dest]) } }
        }
    }

    // MARK: Internals

    private func save() {
        guard let data = try? JSONEncoder().encode(shelf) else { return }
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
        chmod(Self.fileURL.path, 0o600)
    }

    func refreshMissing() {
        missing = shelf.missing { FileManager.default.fileExists(atPath: $0) }
    }

    func loadThumbnails() {
        for item in shelf.items where thumbnails[item.id] == nil && !missing.contains(item.id) {
            let id = item.id
            let req = QLThumbnailGenerator.Request(fileAt: url(item), size: CGSize(width: 96, height: 96), scale: 2, representationTypes: .thumbnail)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { @Sendable rep, _ in
                guard let cg = rep?.cgImage else { return }
                let img = NSImage(cgImage: cg, size: NSSize(width: 48, height: 48))
                Task { @MainActor in ShelfProvider.shared.thumbnails[id] = img }
            }
        }
    }

    private func startScreenshotWatch() {
        guard query == nil, AppModel.shared.screenshotsToShelf else { return }
        started = Date()
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 && kMDItemContentCreationDate > %@", started as NSDate)
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { n in
            let added = (n.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? [])
                .compactMap { $0.value(forAttribute: NSMetadataItemPathKey) as? String }
            MainActor.assumeIsolated { ShelfProvider.shared.add(added.map(URL.init(fileURLWithPath:)), fromScreenshot: true) }
        }
        q.start()
        query = q
    }

    func restartScreenshotWatch() { stop(); startScreenshotWatch() }
}
