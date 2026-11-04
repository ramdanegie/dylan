import AppKit
import DylanCore
import ScreenCaptureKit
import Vision
import UniformTypeIdentifiers

/// Screenshot preferences (design D43), in the app's defaults.
enum ShotPrefs {
    enum After: String, CaseIterable { case notch, studio, saveOnly }
    static var d: UserDefaults { AppModel.store }
    static var after: After { After(rawValue: d.string(forKey: "shot.after") ?? "") ?? .notch }
    static var saveFile: Bool { d.object(forKey: "shot.saveFile") as? Bool ?? false }
    static var folder: URL {
        d.string(forKey: "shot.folder").map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Dylan")
    }
    static var format: String { d.string(forKey: "shot.format") ?? "png" }
    static var hideDesktopIcons: Bool { d.object(forKey: "shot.hideIcons") as? Bool ?? true }
    static var loupe: Bool { d.object(forKey: "shot.loupe") as? Bool ?? true }
    static var windowShadow: Bool { d.object(forKey: "shot.windowShadow") as? Bool ?? true }
    static var retina: Bool { d.object(forKey: "shot.retina") as? Bool ?? true }
    static var autoBlur: Bool { d.object(forKey: "shot.autoBlur") as? Bool ?? true }
    static var retentionDays: Int { d.object(forKey: "shot.retention") as? Int ?? CaptureStore.defaultRetentionDays }
    static var studioBackground: Int { d.object(forKey: "shot.bg") as? Int ?? 5 }   // Senja
}

/// Capture, store and hand off screenshots (FR-88 to FR-90). ScreenCaptureKit, Screen Recording permission.
final class ScreenshotService {
    static let shared = ScreenshotService()

    /// Original captures, so Studio and the editor can always start again (design: "file asli selalu disimpan").
    static var historyDir: URL { Bridge.socketURL.deletingLastPathComponent().appendingPathComponent("Captures") }
    private(set) var lastCapture: URL?

    // MARK: Permission

    var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Asks once (macOS shows its own dialog); returns whether capture can go ahead now.
    func ensurePermission() -> Bool {
        if hasPermission { return true }
        _ = CGRequestScreenCaptureAccess()
        AppModel.shared.center.post(Activity(id: "capture-permission", kind: .notify, priority: .p1, state: .info, symbol: "camera.viewfinder",
                                             label: L("shot.short"), detail: L("shot.needPermission"), startedAt: Date()), now: Date())
        AppModel.shared.scheduleTick()
        return false
    }

    // MARK: Capture

    struct Frozen {
        let screen: NSScreen
        let image: CGImage
        let scale: CGFloat
        /// Windows under the frozen image, front to back, in the screen's AppKit coordinates.
        let windows: [(frame: CGRect, window: SCWindow)]
    }

    /// The whole screen as it is now, without Dylan and (optionally) without desktop icons.
    func freeze(_ screen: NSScreen) async -> Frozen? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == id }) else { return nil }
        let me = getpid()
        let excluded = content.windows.filter { w in
            w.owningApplication?.processID == me
                || (ShotPrefs.hideDesktopIcons && w.owningApplication?.bundleIdentifier == "com.apple.finder" && w.windowLayer < 0)
        }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let config = SCStreamConfiguration()
        let scale = ShotPrefs.retina ? screen.backingScaleFactor : 1
        config.width = Int(screen.frame.width * scale)
        config.height = Int(screen.frame.height * scale)
        config.showsCursor = false
        config.captureResolution = ShotPrefs.retina ? .best : .nominal
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        // Pickable windows: normal layer, visible, not Dylan's, front to back (content.windows is front to back).
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let windows = content.windows.compactMap { w -> (CGRect, SCWindow)? in
            guard w.windowLayer == 0, w.isOnScreen, w.frame.width > 40, w.frame.height > 40, w.owningApplication?.processID != me else { return nil }
            // SCWindow.frame is top-left based on the primary screen; convert to AppKit.
            let f = CGRect(x: w.frame.minX, y: primaryTop - w.frame.maxY, width: w.frame.width, height: w.frame.height)
            return f.intersects(screen.frame) ? (f, w) : nil
        }
        return Frozen(screen: screen, image: image, scale: scale, windows: windows)
    }

    /// One window by itself (its own pixels, even if covered), with or without its shadow.
    func capture(window: SCWindow, scale: CGFloat) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = !ShotPrefs.windowShadow
        config.captureResolution = .best
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// A live region of a screen (scrolling capture frames).
    func capture(region: CGRect, of screen: NSScreen) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == id }) else { return nil }
        let me = getpid()
        let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { $0.owningApplication?.processID == me })
        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        // sourceRect is in the display's points, top-left origin.
        config.sourceRect = CGRect(x: region.minX - screen.frame.minX, y: screen.frame.maxY - region.maxY, width: region.width, height: region.height)
        config.width = Int(region.width * scale)
        config.height = Int(region.height * scale)
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    // MARK: Result

    /// Stores the original, copies it, saves a file if asked, and shows the result in the notch (D40).
    func finished(_ image: CGImage, kind: String = "image") {
        let url = Self.store(image, in: Self.historyDir, ext: "png")
        lastCapture = url
        pruneHistory()
        if ShotPrefs.after != .saveOnly {
            if ShotPrefs.d.bool(forKey: "shot.autoBeautify"), let url, let pretty = StudioModel(original: image, url: url).render() { copy(pretty) } else { copy(image) }
        }
        if ShotPrefs.saveFile || ShotPrefs.after == .saveOnly { _ = Self.store(image, in: ShotPrefs.folder, ext: ShotPrefs.format) }
        if ShotPrefs.after == .studio, let url { StudioWindow.open(url); return }
        guard let url else { return }
        let now = Date()
        AppModel.shared.center.post(Activity(
            id: "capture-\(url.lastPathComponent)", kind: .capture, priority: .p2, state: .success, symbol: "camera.viewfinder",
            label: ShotPrefs.after == .saveOnly ? L("shot.saved") : L("shot.copied"), value: "\(image.width / max(1, Int(screenScale)))×\(image.height / max(1, Int(screenScale)))",
            detail: L("shot.copiedDetail", image.width / max(1, Int(screenScale)), image.height / max(1, Int(screenScale))),
            genericDetail: L("shot.copied"), url: "capture:" + url.path, startedAt: now), now: now)
        AppModel.shared.scheduleTick()
    }

    private var screenScale: CGFloat { ShotPrefs.retina ? (NSScreen.main?.backingScaleFactor ?? 2) : 1 }

    func copy(_ image: CGImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let rep = NSBitmapImageRep(cgImage: image)
        if let png = rep.representation(using: .png, properties: [:]) { pb.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
    }

    /// Writes PNG/JPG/WebP with a free "Dylan <date>" name; 0700 folder, never overwrites.
    @discardableResult
    static func store(_ image: CGImage, in dir: URL, ext: String) -> URL? {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = Shelf.freePath(dir: dir.path, name: CaptureStore.fileName(Date(), ext: ext))
        let url = URL(fileURLWithPath: path)
        let type: UTType = ext == "jpg" ? .jpeg : (ext == "webp" ? .webP : .png)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            // No WebP encoder on this Mac: fall back to PNG rather than lose the capture.
            return ext == "webp" ? store(image, in: dir, ext: "png") : nil
        }
        CGImageDestinationAddImage(dest, image, ext == "jpg" ? [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary : nil)
        return CGImageDestinationFinalize(dest) ? url : nil
    }

    static var canWriteWebP: Bool {
        (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(UTType.webP.identifier)
    }

    func pruneHistory() {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: Self.historyDir, includingPropertiesForKeys: [.creationDateKey])) ?? []).compactMap { u -> (String, Date)? in
            guard let d = try? u.resourceValues(forKeys: [.creationDateKey]).creationDate else { return nil }
            return (u.path, d)
        }
        for p in CaptureStore.expired(files.map { (path: $0.0, date: $0.1) }, now: Date(), days: ShotPrefs.retentionDays) { try? fm.removeItem(atPath: p) }
    }

    var history: [URL] {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(at: Self.historyDir, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { ["png", "jpg", "webp"].contains($0.pathExtension.lowercased()) }
            .sorted { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
                    > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
    }

    func clearHistory() {
        for u in history { try? FileManager.default.removeItem(at: u) }
        lastCapture = nil
    }

    // MARK: Notch actions (D40)

    func perform(_ action: String, _ arg: String) {
        let url = URL(fileURLWithPath: arg)
        switch action {
        case "beautify": StudioWindow.open(url)
        case "annotate": StudioWindow.open(url, annotate: true)
        case "save":
            guard let img = NSImage(contentsOf: url).flatMap(VisionTools.cgImage), let saved = Self.store(img, in: ShotPrefs.folder, ext: ShotPrefs.format) else { return }
            NSWorkspace.shared.activateFileViewerSelecting([saved])
        case "pin": PinWindow.pin(url)
        case "text": if let img = NSImage(contentsOf: url).flatMap(VisionTools.cgImage) { finishedText(img) }
        case "openLink": if let u = URL(string: arg), u.scheme?.hasPrefix("http") == true { NSWorkspace.shared.open(u) }
        case "showText":
            let alert = NSAlert()
            alert.messageText = L("shot.text")
            alert.informativeText = arg
            NSApp.activate()
            alert.runModal()
        default: break
        }
    }

    /// ⌥⇧E: the last capture in Studio.
    func openLast() {
        if let u = lastCapture ?? history.first { StudioWindow.open(u) }
    }

    // MARK: Text (OCR) and QR (FR-90)

    func finishedText(_ image: CGImage) {
        Task {
            let text = await VisionTools.copyText(from: image)
            let link = await Self.qrLink(in: image)
            let now = Date()
            let lines = text?.split(separator: "\n").count ?? 0
            AppModel.shared.center.post(Activity(
                id: "capture-text-\(now.timeIntervalSince1970)", kind: .capture, priority: .p2, state: text == nil && link == nil ? .info : .success,
                symbol: "text.viewfinder", label: text == nil ? L("shot.noText") : L("shot.text"),
                value: text == nil ? "" : "\(lines)",
                detail: text.map { L("shot.textDetail", lines) + " · " + TextRules.truncateTail(TextRules.singleLine($0), max: 80) } ?? (link ?? L("shot.noText")),
                genericDetail: L("shot.text"), url: link.map { "qr:" + $0 } ?? (text.map { "text:" + $0 }), startedAt: now), now: now)
            AppModel.shared.scheduleTick()
        }
    }

    static func qrLink(in image: CGImage) async -> String? {
        await Task.detached {
            let req = VNDetectBarcodesRequest()
            req.symbologies = [.qr]
            try? VNImageRequestHandler(cgImage: image).perform([req])
            return (req.results ?? []).compactMap(\.payloadStringValue).first { URL(string: $0)?.scheme?.hasPrefix("http") == true }
        }.value
    }
}
