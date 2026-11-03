import AppKit
import ApplicationServices
import DylanCore

/// Clipboard history (FR-20) with secret protection (FR-22, PRD §2.8).
/// macOS has no change notification for the pasteboard, so `changeCount` is polled every 0.5 s,
/// and only while the feature is on.
final class ClipboardProvider {
    static let shared = ClipboardProvider()

    private(set) var history = ClipboardHistory()
    /// Images stay in memory only (latest 20).
    private(set) var images: [UUID: NSImage] = [:]
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount
    private var saveWork: DispatchWorkItem?
    var ignoredApps: Set<String> = SecretDetector.defaultIgnoredApps

    static var fileURL: URL {
        Bridge.socketURL.deletingLastPathComponent().appendingPathComponent("clipboard.json")
    }

    func start() {
        guard timer == nil else { return }
        load()
        lastChange = NSPasteboard.general.changeCount
        let t = Timer(timeInterval: 0.5, repeats: true) { _ in MainActor.assumeIsolated { ClipboardProvider.shared.poll() } }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else {
            if history.items.contains(where: \.secret) { expireSecrets() }
            return
        }
        lastChange = pb.changeCount
        let types = Set((pb.types ?? []).map(\.rawValue))
        // Password managers mark their copies; also skip anything copied while they are in front.
        guard types.isDisjoint(with: SecretDetector.skippedTypes),
              !ignoredApps.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "") else { return }
        let source = NSWorkspace.shared.frontmostApplication?.localizedName
        let now = Date()

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            add(.init(kind: .file, text: urls.map(\.path).joined(separator: "\n"), date: now, sourceApp: source))
        } else if let s = pb.string(forType: .string), !s.isEmpty {
            add(.init(kind: .text, text: String(s.prefix(100_000)), date: now, sourceApp: source, secret: SecretDetector.isSecret(s)))
        } else if let img = NSImage(pasteboard: pb) {
            let item = ClipboardHistory.Item(kind: .image, text: "\(Int(img.size.width))×\(Int(img.size.height))", date: now, sourceApp: source)
            images[item.id] = img
            add(item)
            if images.count > 20 {
                let keep = Set(history.items.filter { $0.kind == .image }.prefix(20).map(\.id))
                images = images.filter { keep.contains($0.key) }
            }
        }
    }

    private func add(_ item: ClipboardHistory.Item) {
        history.add(item)
        AppModel.shared.clipboardChanged()
        scheduleSave()
    }

    private func expireSecrets() {
        let before = history.items.count
        history.trim(now: Date())
        if history.items.count != before { AppModel.shared.clipboardChanged() }
    }

    // MARK: Actions

    /// Copies an item back to the pasteboard; `paste` also sends ⌘V when Accessibility is granted.
    func copy(_ item: ClipboardHistory.Item, paste: Bool = false) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text: pb.setString(item.text, forType: .string)
        case .file: pb.writeObjects(item.text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) as NSURL })
        case .image: if let img = images[item.id] { pb.writeObjects([img]) }
        }
        lastChange = pb.changeCount
        history.add(ClipboardHistory.Item(id: item.id, kind: item.kind, text: item.text, date: Date(), pinned: item.pinned,
                                          sourceApp: item.sourceApp, secret: item.secret))
        AppModel.shared.clipboardChanged()
        guard paste, AXIsProcessTrusted() else { return }
        AppModel.shared.notchState = .closed
        // Give focus back to the previous app before typing ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let src = CGEventSource(stateID: .privateState)
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: down)   // V
                e?.flags = .maskCommand
                e?.post(tap: .cghidEventTap)
            }
        }
    }

    func copyText(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    func togglePin(_ id: UUID) { history.togglePin(id); AppModel.shared.clipboardChanged(); scheduleSave() }

    func clearAll() {
        history.items.removeAll()
        images.removeAll()
        try? FileManager.default.removeItem(at: Self.fileURL)
        AppModel.shared.clipboardChanged()
    }

    // MARK: Storage (0600, secrets never written)

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = history.persistable
        let url = Self.fileURL
        // @Sendable: runs on a background queue; a main-actor closure here traps at runtime.
        let w = DispatchWorkItem { @Sendable in
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            try? data.write(to: url, options: [.atomic])
            chmod(url.path, 0o600)
        }
        saveWork = w
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: w)
    }

    private func load() {
        guard history.items.isEmpty, let d = try? Data(contentsOf: Self.fileURL),
              let h = try? JSONDecoder().decode(ClipboardHistory.self, from: d) else { return }
        history = h
        // Image items had their data in memory only.
        history.items.removeAll { $0.kind == .image }
        history.trim(now: Date())
    }
}
