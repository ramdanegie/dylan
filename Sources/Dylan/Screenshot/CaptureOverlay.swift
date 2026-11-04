import AppKit
import DylanCore
import ScreenCaptureKit

/// The capture overlay (design D39): the screen is frozen first, then the user picks an area, a window or the
/// whole screen on top of the frozen picture. A notch-shaped bar at the top switches modes.
final class CaptureOverlay {
    static let shared = CaptureOverlay()

    enum Mode: Int, CaseIterable {
        case area = 1, window, screen, scroll, text
        var key: String { "\(rawValue)" }
        var title: String { L("shot.mode.\(self)") }
    }

    private var panel: NSPanel?
    private var countdown: Timer?
    /// Set while ScreenCaptureKit freezes the screen, so a second shortcut press cannot open a second overlay.
    private var freezing = false
    var isActive: Bool { panel != nil || countdown != nil || freezing }
    static let timers = [0, 3, 5, 10]

    /// Starts a capture. `delay` (seconds) waits before freezing the screen, so menus can be opened first.
    func start(_ mode: Mode, delay: Int = 0) {
        // Pressing a capture shortcut again during the countdown cancels it.
        if countdown != nil { cancelCountdown(); return }
        guard !isActive, !ScrollCapture.shared.isActive, ScreenshotService.shared.ensurePermission() else { return }
        if delay > 0 { runCountdown(mode, delay); return }
        freeze(mode)
    }

    private var left = 0
    private var pendingMode: Mode = .area

    private func runCountdown(_ mode: Mode, _ seconds: Int) {
        left = seconds
        pendingMode = mode
        showCountdown()
        let t = Timer(timeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { CaptureOverlay.shared.countdownTick() } }
        RunLoop.main.add(t, forMode: .common)
        countdown = t
    }

    private func showCountdown() {
        let now = Date()
        AppModel.shared.center.upsert(Activity(id: "capture-timer", kind: .capture, priority: .p2, state: .running, symbol: "timer",
                                               label: L("shot.short"), value: "\(left)", detail: L("shot.timerDetail", left), startedAt: now))
        AppModel.shared.scheduleTick()
    }

    private func countdownTick() {
        left -= 1
        if left > 0 { showCountdown(); return }
        countdown?.invalidate()
        countdown = nil
        AppModel.shared.removeIfPresent("capture-timer", now: Date())
        // Give the notch a moment to collapse so it is not in the picture.
        let mode = pendingMode
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { MainActor.assumeIsolated { CaptureOverlay.shared.freeze(mode) } }
    }

    private func freeze(_ mode: Mode) {
        let mouse = NSEvent.mouseLocation
        guard !freezing, panel == nil, let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        freezing = true
        Task {
            let frozen = await ScreenshotService.shared.freeze(screen)
            CaptureOverlay.shared.freezing = false
            guard let frozen else { return }
            // ⌥⇧3: the whole screen at once, like ⇧⌘3.
            if mode == .screen { ScreenshotService.shared.finished(frozen.image); return }
            CaptureOverlay.shared.show(frozen, mode: mode)
        }
    }

    private func show(_ frozen: ScreenshotService.Frozen, mode: Mode) {
        guard panel == nil else { return }
        let p = KeyPanel(contentRect: frozen.screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = true
        p.hasShadow = false
        p.sharingType = .none
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let v = CaptureView(frozen: frozen, mode: mode)
        p.contentView = v
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(v)
        NSCursor.crosshair.push()
        panel = p
    }

    func close() {
        guard panel != nil else { return }
        NSCursor.pop()
        panel?.orderOut(nil)
        panel = nil
    }

    func cancelCountdown() {
        countdown?.invalidate(); countdown = nil
        AppModel.shared.removeIfPresent("capture-timer", now: Date())
    }
}

/// A borderless panel that can take keys without activating Dylan.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Draws the frozen screen, the selection, the loupe and the mode bar; handles mouse and keys (D39).
final class CaptureView: NSView {
    private let frozen: ScreenshotService.Frozen
    private var mode: CaptureOverlay.Mode
    private var start: CGPoint?
    private var selection: CGRect?
    private var mouse: CGPoint = .zero
    private var hovered: (frame: CGRect, window: SCWindow)?
    private let bitmap: NSBitmapImageRep
    private var barButtons: [(rect: CGRect, mode: CaptureOverlay.Mode)] = []
    private var timerButton: CGRect = .zero
    private var timer = 0
    private var copiedHex: String?
    private var timerWork: DispatchWorkItem?

    init(frozen: ScreenshotService.Frozen, mode: CaptureOverlay.Mode) {
        self.frozen = frozen
        self.mode = mode
        bitmap = NSBitmapImageRep(cgImage: frozen.image)
        super.init(frame: CGRect(origin: .zero, size: frozen.screen.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
        mouse = convertToLocal(NSEvent.mouseLocation)
        updateHover()
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func convertToLocal(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - frozen.screen.frame.minX, y: p.y - frozen.screen.frame.minY) }
    private var bounds0: CGRect { CGRect(origin: .zero, size: frozen.screen.frame.size) }

    // MARK: Drawing

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .high
        ctx.draw(frozen.image, in: bounds0)
        // Dim everything but the selection / hovered window.
        let hole = selection ?? (mode == .window ? hovered.map { CGRect(origin: convertToLocal($0.frame.origin), size: $0.frame.size) } : nil)
        ctx.setFillColor(NSColor.black.withAlphaComponent(mode == .screen ? 0.12 : 0.35).cgColor)
        ctx.addRect(bounds0)
        if let hole { ctx.addRect(hole) }
        ctx.fillPath(using: .evenOdd)
        if let hole {
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(hole.insetBy(dx: -0.5, dy: -0.5))
            let label = mode == .window ? (hovered?.window.owningApplication?.applicationName ?? "") + " · " + L("shot.clickToCapture")
                                         : "\(Int(hole.width)) × \(Int(hole.height))"
            drawPill(label, at: CGPoint(x: hole.minX, y: hole.minY - 26), ctx: ctx)
        } else if mode == .area || mode == .text || mode == .scroll {
            // Crosshair lines across the screen.
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(1)
            ctx.strokeLineSegments(between: [CGPoint(x: mouse.x, y: 0), CGPoint(x: mouse.x, y: bounds0.height),
                                             CGPoint(x: 0, y: mouse.y), CGPoint(x: bounds0.width, y: mouse.y)])
        }
        if ShotPrefs.loupe && mode != .window && mode != .screen { drawLoupe(ctx) }
        drawModeBar(ctx)
    }

    private func drawPill(_ text: String, at p: CGPoint, ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white]
        let s = NSAttributedString(string: text, attributes: attrs)
        let size = s.size()
        var r = CGRect(x: p.x, y: p.y, width: size.width + 16, height: 22)
        r.origin.y = max(4, r.origin.y)
        r.origin.x = min(max(4, r.origin.x), bounds0.width - r.width - 4)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 11, cornerHeight: 11, transform: nil))
        ctx.fillPath()
        s.draw(at: CGPoint(x: r.minX + 8, y: r.minY + (22 - size.height) / 2))
    }

    /// 8× magnified pixels around the cursor, with coordinates and the pixel's hex color.
    private func drawLoupe(_ ctx: CGContext) {
        let px = Int((mouse.x) * frozen.scale), py = Int((bounds0.height - mouse.y) * frozen.scale)
        let n = 15, zoom: CGFloat = 8
        let src = CGRect(x: px - n / 2, y: py - n / 2, width: n, height: n)
        guard let crop = frozen.image.cropping(to: src) else { return }
        let size = CGFloat(n) * zoom
        var origin = CGPoint(x: mouse.x + 20, y: mouse.y - size - 40)
        if origin.x + size > bounds0.width { origin.x = mouse.x - size - 20 }
        if origin.y < 0 { origin.y = mouse.y + 20 }
        let r = CGRect(origin: origin, size: CGSize(width: size, height: size))
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.clip()
        ctx.interpolationQuality = .none
        ctx.draw(crop, in: r)
        ctx.restoreGState()
        // Center pixel outline.
        let c = CGRect(x: r.midX - zoom / 2, y: r.midY - zoom / 2, width: zoom, height: zoom)
        ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(1.5); ctx.stroke(c)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor); ctx.setLineWidth(2)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil)); ctx.strokePath()
        let hex = pixelHex(px, py) ?? "-"
        let pt = CGPoint(x: Int(mouse.x), y: Int(bounds0.height - mouse.y))
        drawPill("\(Int(pt.x)), \(Int(pt.y)) · \(copiedHex == hex ? L("shot.copiedHex") : hex)", at: CGPoint(x: r.minX, y: r.minY - 26), ctx: ctx)
    }

    private func pixelHex(_ x: Int, _ y: Int) -> String? {
        guard x >= 0, y >= 0, x < bitmap.pixelsWide, y < bitmap.pixelsHigh, let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }

    /// The notch grows into the mode picker (D39): modes 1–5 and the timer.
    private func drawModeBar(_ ctx: CGContext) {
        let modes = CaptureOverlay.Mode.allCases
        let itemW: CGFloat = 92, h: CGFloat = 40
        let w = itemW * CGFloat(modes.count) + 70
        let bar = CGRect(x: bounds0.midX - w / 2, y: bounds0.height - h - 6, width: w, height: h + 6)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(CGPath(roundedRect: bar.insetBy(dx: 0, dy: -12).offsetBy(dx: 0, dy: 6), cornerWidth: 18, cornerHeight: 18, transform: nil))
        ctx.fillPath()
        barButtons = []
        for (i, m) in modes.enumerated() {
            let r = CGRect(x: bar.minX + 8 + CGFloat(i) * itemW, y: bar.minY + 6, width: itemW - 6, height: 28)
            barButtons.append((r, m))
            if m == mode {
                ctx.setFillColor(NSColor.white.withAlphaComponent(0.18).cgColor)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: 14, cornerHeight: 14, transform: nil)); ctx.fillPath()
            }
            let t = NSAttributedString(string: "\(m.key)  \(m.title)", attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: m == mode ? .semibold : .regular),
                .foregroundColor: m == mode ? NSColor.white : NSColor.white.withAlphaComponent(0.6)])
            let s = t.size()
            t.draw(at: CGPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2))
        }
        timerButton = CGRect(x: bar.maxX - 60, y: bar.minY + 6, width: 52, height: 28)
        let tt = NSAttributedString(string: timer == 0 ? "⏱ —" : "⏱ \(timer)s", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                                                                                         .foregroundColor: NSColor.white.withAlphaComponent(0.8)])
        tt.draw(at: CGPoint(x: timerButton.midX - tt.size().width / 2, y: timerButton.midY - tt.size().height / 2))
        drawPill(L("shot.hint.\(mode)"), at: CGPoint(x: bar.midX - 120, y: bar.minY - 30), ctx: ctx)
    }

    // MARK: Mouse

    override func mouseMoved(with e: NSEvent) {
        mouse = convert(e.locationInWindow, from: nil)
        updateHover()
        needsDisplay = true
    }

    private func updateHover() {
        guard mode == .window else { hovered = nil; return }
        let g = CGPoint(x: mouse.x + frozen.screen.frame.minX, y: mouse.y + frozen.screen.frame.minY)
        hovered = frozen.windows.first { $0.frame.contains(g) }
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if let b = barButtons.first(where: { $0.rect.contains(p) }) { switchMode(b.mode); return }
        if timerButton.contains(p) {
            timer = CaptureOverlay.timers[(CaptureOverlay.timers.firstIndex(of: timer)! + 1) % CaptureOverlay.timers.count]
            needsDisplay = true
            // A second after the last click: close, count down in the notch, then freeze the screen again.
            timerWork?.cancel()
            guard timer > 0 else { return }
            let (m, t) = (mode, timer)
            let w = DispatchWorkItem { MainActor.assumeIsolated { CaptureOverlay.shared.close(); CaptureOverlay.shared.start(m, delay: t) } }
            timerWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: w)
            return
        }
        start = p
        selection = nil
    }

    override func mouseDragged(with e: NSEvent) {
        guard let start, mode != .window, mode != .screen else { return }
        mouse = convert(e.locationInWindow, from: nil)
        let ratio: CGFloat? = e.modifierFlags.contains(.shift) ? 1 : nil
        selection = CaptureSelection.rect(from: start, to: mouse, lockRatio: ratio, fromCenter: e.modifierFlags.contains(.option), bounds: bounds0)
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        defer { start = nil }
        guard start != nil else { return }
        switch mode {
        case .window:
            guard let w = hovered?.window else { return }
            finish { await ScreenshotService.shared.capture(window: w, scale: self.frozen.scale) }
        case .screen:
            finishImage(frozen.image)
        case .area, .text, .scroll:
            guard let sel = selection, !CaptureSelection.isClick(sel) else { selection = nil; needsDisplay = true; return }
            confirm(sel)
        }
    }

    private func confirm(_ sel: CGRect) {
        let global = sel.offsetBy(dx: frozen.screen.frame.minX, dy: frozen.screen.frame.minY)
        let px = CaptureSelection.pixelRect(global, screen: frozen.screen.frame, scale: frozen.scale)
        guard let crop = frozen.image.cropping(to: px) else { return }
        let screen = frozen.screen
        let mode = self.mode
        CaptureOverlay.shared.close()
        switch mode {
        case .text: ScreenshotService.shared.finishedText(crop)
        case .scroll: ScrollCapture.shared.start(region: global, screen: screen)
        default: ScreenshotService.shared.finished(crop)
        }
    }

    private func finishImage(_ image: CGImage) {
        CaptureOverlay.shared.close()
        ScreenshotService.shared.finished(image)
    }

    private func finish(_ capture: @escaping @MainActor () async -> CGImage?) {
        CaptureOverlay.shared.close()
        Task { if let img = await capture() { ScreenshotService.shared.finished(img) } }
    }

    private func switchMode(_ m: CaptureOverlay.Mode) {
        mode = m
        selection = nil
        updateHover()
        if m == .screen { finishImage(frozen.image); return }
        needsDisplay = true
    }

    // MARK: Keys (D39: 1–5 / Space mode, Esc cancel, arrows 1 pt, Return confirm, C copies hex)

    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 53: timerWork?.cancel(); CaptureOverlay.shared.close(); return               // Esc
        case 36, 76: if let s = selection { confirm(s) }; return                          // Return
        case 49:                                                                          // Space
            let next = CaptureOverlay.Mode(rawValue: mode.rawValue % CaptureOverlay.Mode.allCases.count + 1)!
            switchMode(next); return
        case 123, 124, 125, 126:
            guard let s = selection else { return }
            let step: CGFloat = e.modifierFlags.contains(.shift) ? 10 : 1
            let d: (CGFloat, CGFloat) = e.keyCode == 123 ? (-step, 0) : e.keyCode == 124 ? (step, 0) : e.keyCode == 125 ? (0, -step) : (0, step)
            selection = CaptureSelection.nudge(s, dx: d.0, dy: d.1, bounds: bounds0)
            needsDisplay = true
            return
        default: break
        }
        guard let ch = e.charactersIgnoringModifiers?.lowercased() else { return }
        if let n = Int(ch), let m = CaptureOverlay.Mode(rawValue: n) { switchMode(m); return }
        if ch == "c", let hex = pixelHex(Int(mouse.x * frozen.scale), Int((bounds0.height - mouse.y) * frozen.scale)) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            copiedHex = hex
            needsDisplay = true
        }
    }
}
