import AppKit
import DylanCore

/// Scrolling capture (FR-91, design D42): the chosen region is captured ~7 times a second while the user
/// scrolls (or Space scrolls for them); each frame is matched to the previous one by its pixel rows and only
/// the newly revealed rows are kept. Sticky headers are dropped; 20 000 px at most; Esc or Selesai saves.
final class ScrollCapture {
    static let shared = ScrollCapture()

    private var region: CGRect = .zero
    private var screen: NSScreen?
    private var timer: Timer?
    private var hud: NSPanel?
    private var border: NSPanel?
    private var keyMonitor: Any?
    private var pieces: [CGImage] = []
    private var lastRows: [UInt64] = []
    private var height = 0
    private var busy = false
    private var lastMove = Date()
    private var autoScroll = false
    var isActive: Bool { timer != nil }

    func start(region: CGRect, screen: NSScreen) {
        guard !isActive else { return }
        self.region = region
        self.screen = screen
        pieces = []; lastRows = []; height = 0; lastMove = Date(); autoScroll = false
        showChrome()
        let t = Timer(timeInterval: 0.15, repeats: true) { _ in MainActor.assumeIsolated { ScrollCapture.shared.tick() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private func tick() {
        guard !busy, let screen else { return }
        busy = true
        Task {
            let img = await ScreenshotService.shared.capture(region: region, of: screen)
            busy = false
            guard let img else { return }
            add(img)
            if autoScroll { Self.scroll(lines: -6) }
            // At the end of the page the frames stop changing: finish after 2 s without movement once scrolling began.
            if pieces.count > 1, Date().timeIntervalSince(lastMove) > 2 { finish() }
            if height >= ScrollStitch.maxHeight { finish() }
        }
    }

    private func add(_ img: CGImage) {
        let rows = Self.rowHashes(img)
        guard !lastRows.isEmpty else {
            pieces = [img]; lastRows = rows; height = img.height; lastMove = Date(); updateHUD(); return
        }
        let sticky = ScrollStitch.stickyRows(lastRows, rows)
        guard let shift = ScrollStitch.shift(lastRows, rows, sticky: sticky) else { lastRows = rows; return }
        let keep = ScrollStitch.newRows(height: img.height, shift: shift)
        if let slice = img.cropping(to: CGRect(x: 0, y: keep.lowerBound, width: img.width, height: keep.count)) {
            pieces.append(slice)
            height += keep.count
            lastMove = Date()
        }
        lastRows = rows
        updateHUD()
    }

    /// FNV-1a of every 4th pixel per row: enough to tell rows apart, cheap enough for ~7 frames a second.
    nonisolated static func rowHashes(_ img: CGImage) -> [UInt64] {
        let w = img.width, h = img.height, bpr = w * 4
        var data = [UInt8](repeating: 0, count: bpr * h)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var out = [UInt64](repeating: 0, count: h)
        for y in 0..<h {
            var hash: UInt64 = 0xcbf29ce484222325
            var x = 0
            while x < bpr { hash = (hash ^ UInt64(data[y * bpr + x])) &* 0x100000001b3; hash = (hash ^ UInt64(data[y * bpr + x + 1])) &* 0x100000001b3; x += 16 }
            out[y] = hash
        }
        return out
    }

    func finish() {
        guard isActive else { return }
        timer?.invalidate(); timer = nil
        hideChrome()
        guard let image = Self.join(pieces) else { return }
        pieces = []
        ScreenshotService.shared.finished(image)
    }

    nonisolated static func join(_ pieces: [CGImage]) -> CGImage? {
        guard let first = pieces.first else { return nil }
        let w = first.width, h = min(pieces.reduce(0) { $0 + $1.height }, ScrollStitch.maxHeight * 2)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var y = h
        for p in pieces {
            y -= p.height
            if y < 0 { break }
            ctx.draw(p, in: CGRect(x: 0, y: y, width: p.width, height: p.height))
        }
        return ctx.makeImage()
    }

    /// Space: Dylan scrolls for the user (needs permission to post events; asked on that key press).
    private func toggleAutoScroll() {
        guard CGPreflightPostEventAccess() else { _ = CGRequestPostEventAccess(); return }
        autoScroll.toggle()
        // The wheel goes to whatever is under the pointer: put it in the region (global coords are top-left based).
        if autoScroll { CGWarpMouseCursorPosition(CGPoint(x: region.midX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - region.midY)) }
    }

    nonisolated static func scroll(lines: Int32) {
        CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
    }

    // MARK: Chrome: a click-through border and a small HUD with the height and Selesai

    private var hudLabel: NSTextField?

    private func showChrome() {
        let b = NSPanel(contentRect: region.insetBy(dx: -3, dy: -3), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        b.isOpaque = false; b.backgroundColor = .clear; b.ignoresMouseEvents = true; b.level = .screenSaver; b.sharingType = .none
        let v = NSView(frame: CGRect(origin: .zero, size: b.frame.size))
        v.wantsLayer = true
        v.layer?.borderColor = NSColor.systemYellow.cgColor
        v.layer?.borderWidth = 2
        v.layer?.cornerRadius = 4
        b.contentView = v
        b.orderFrontRegardless()
        border = b

        let size = CGSize(width: 300, height: 44)
        let origin = CGPoint(x: region.midX - size.width / 2, y: max(region.minY - size.height - 10, (screen?.frame.minY ?? 0) + 10))
        let h = KeyPanel(contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        h.isOpaque = false; h.backgroundColor = .clear; h.level = .screenSaver; h.sharingType = .none
        let box = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        box.material = .hudWindow; box.state = .active; box.wantsLayer = true; box.layer?.cornerRadius = 12
        let label = NSTextField(labelWithString: L("shot.scrollHint", 0))
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.frame = CGRect(x: 14, y: 13, width: 190, height: 18)
        let done = NSButton(title: L("shot.done"), target: self, action: #selector(doneClicked))
        done.bezelStyle = .rounded
        done.frame = CGRect(x: 206, y: 8, width: 84, height: 28)
        box.addSubview(label); box.addSubview(done)
        h.contentView = box
        h.orderFrontRegardless()
        hud = h
        hudLabel = label
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { e in
            let code = e.keyCode
            MainActor.assumeIsolated {
                if code == 53 { ScrollCapture.shared.finish() }            // Esc keeps what was captured
                if code == 49 { ScrollCapture.shared.toggleAutoScroll() }  // Space
            }
        }
    }

    @objc private func doneClicked() { finish() }

    private func updateHUD() {
        let pts = Int(CGFloat(height) / (screen?.backingScaleFactor ?? 2))
        hudLabel?.stringValue = L("shot.scrollHint", pts)
    }

    private func hideChrome() {
        border?.orderOut(nil); border = nil
        hud?.orderOut(nil); hud = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
