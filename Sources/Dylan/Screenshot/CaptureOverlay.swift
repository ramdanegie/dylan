import AppKit
import Carbon.HIToolbox
import DylanCore
import QuartzCore
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
        // Esc must work even when the panel did not become key (shortcut pressed while another app has focus,
        // so keyDown never reaches the overlay). A Carbon hotkey needs no permission and only lives while open.
        Hotkeys.register(id: Self.escapeHotkey, keyCode: kVK_Escape, modifiers: 0) { CaptureOverlay.shared.cancel() }
    }

    private static let escapeHotkey: UInt32 = 40

    /// Esc: drop the selection and any pending timer.
    func cancel() {
        (panel?.contentView as? CaptureView)?.cancelTimer()
        close()
    }

    func close() {
        guard panel != nil else { return }
        Hotkeys.unregister(id: Self.escapeHotkey)
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

    // Smooth crosshair: the frozen picture, the dimming, the selection border and the crosshair are layers
    // (composited on the GPU); only the small loupe, labels and mode bar are drawn, and only where they changed.
    private let backdrop = OverlayView.PassThrough()
    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let crossH = CALayer(), crossV = CALayer()
    private let overlay = OverlayView()
    private var lastHole: CGRect??
    private var lastRects: [CGRect] = []

    init(frozen: ScreenshotService.Frozen, mode: CaptureOverlay.Mode) {
        self.frozen = frozen
        self.mode = mode
        bitmap = NSBitmapImageRep(cgImage: frozen.image)
        super.init(frame: CGRect(origin: .zero, size: frozen.screen.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
        wantsLayer = true
        // Layer-hosting backdrop: we own its layer tree.
        let root = CALayer()
        backdrop.layer = root
        backdrop.wantsLayer = true
        backdrop.frame = bounds0
        imageLayer.contents = frozen.image
        imageLayer.contentsScale = frozen.scale
        imageLayer.contentsGravity = .resize
        dimLayer.fillRule = .evenOdd
        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.cgColor
        borderLayer.lineWidth = 1
        for l in [crossH, crossV] { l.backgroundColor = NSColor.white.withAlphaComponent(0.5).cgColor }
        for l in [imageLayer, dimLayer, borderLayer, crossH, crossV] {
            l.frame = bounds0
            l.contentsScale = frozen.scale
            root.addSublayer(l)
        }
        addSubview(backdrop)
        overlay.frame = bounds0
        overlay.draw = { [unowned self] in self.drawOverlay($0) }
        addSubview(overlay)
        mouse = convertToLocal(NSEvent.mouseLocation)
        updateHover()
        refresh(full: true)
    }

    func cancelTimer() { timerWork?.cancel() }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func convertToLocal(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - frozen.screen.frame.minX, y: p.y - frozen.screen.frame.minY) }
    private var bounds0: CGRect { CGRect(origin: .zero, size: frozen.screen.frame.size) }

    // MARK: Drawing

    /// Selection, or the hovered window in window mode.
    private var hole: CGRect? {
        selection ?? (mode == .window ? hovered.map { CGRect(origin: convertToLocal($0.frame.origin), size: $0.frame.size) } : nil)
    }

    private var holeLabel: String? {
        guard let hole else { return nil }
        return mode == .window ? (hovered?.window.owningApplication?.applicationName ?? "") + " · " + L("shot.clickToCapture")
                               : "\(Int(hole.width)) × \(Int(hole.height))"
    }

    /// Moves the layers and invalidates only what the loupe and labels covered before and cover now.
    private func refresh(full: Bool = false) {
        let hole = self.hole
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if full || lastHole != .some(hole) {
            let p = CGMutablePath()
            p.addRect(bounds0)
            if let hole { p.addRect(hole) }
            dimLayer.path = p
            dimLayer.fillColor = NSColor.black.withAlphaComponent(mode == .screen ? 0.12 : 0.35).cgColor
            borderLayer.path = hole.map { CGPath(rect: $0.insetBy(dx: -0.5, dy: -0.5), transform: nil) }
            lastHole = .some(hole)
        }
        let cross = hole == nil && (mode == .area || mode == .text || mode == .scroll)
        crossH.isHidden = !cross
        crossV.isHidden = !cross
        crossV.frame = CGRect(x: mouse.x - 0.5, y: 0, width: 1, height: bounds0.height)
        crossH.frame = CGRect(x: 0, y: mouse.y - 0.5, width: bounds0.width, height: 1)
        CATransaction.commit()
        let rects = [hole.flatMap { h in holeLabel.map { pillRect($0, at: CGPoint(x: h.minX, y: h.minY - 26)) } }, loupeArea()].compactMap { $0 }
        if full { overlay.needsDisplay = true } else { for r in lastRects + rects { overlay.setNeedsDisplay(r.insetBy(dx: -4, dy: -4)) } }
        lastRects = rects
    }

    private func drawOverlay(_ ctx: CGContext) {
        if let hole, let label = holeLabel { drawPill(label, at: CGPoint(x: hole.minX, y: hole.minY - 26), ctx: ctx) }
        if showsLoupe { drawLoupe(ctx) }
        drawModeBar(ctx)
    }

    private var showsLoupe: Bool { ShotPrefs.loupe && mode != .window && mode != .screen }

    private func pillRect(_ text: String, at p: CGPoint) -> CGRect {
        let size = NSAttributedString(string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)]).size()
        var r = CGRect(x: p.x, y: p.y, width: size.width + 16, height: 22)
        r.origin.y = max(4, r.origin.y)
        r.origin.x = min(max(4, r.origin.x), bounds0.width - r.width - 4)
        return r
    }

    private func drawPill(_ text: String, at p: CGPoint, ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white]
        let s = NSAttributedString(string: text, attributes: attrs)
        let size = s.size()
        let r = pillRect(text, at: p)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 11, cornerHeight: 11, transform: nil))
        ctx.fillPath()
        s.draw(at: CGPoint(x: r.minX + 8, y: r.minY + (22 - size.height) / 2))
    }

    /// 8× magnified pixels around the cursor, with coordinates and the pixel's hex color.
    private static let loupeN = 15, loupeZoom: CGFloat = 8

    private var loupeRect: CGRect {
        let size = CGFloat(Self.loupeN) * Self.loupeZoom
        var origin = CGPoint(x: mouse.x + 20, y: mouse.y - size - 40)
        if origin.x + size > bounds0.width { origin.x = mouse.x - size - 20 }
        if origin.y < 0 { origin.y = mouse.y + 20 }
        return CGRect(origin: origin, size: CGSize(width: size, height: size))
    }

    private var loupeText: String {
        let px = Int(mouse.x * frozen.scale), py = Int((bounds0.height - mouse.y) * frozen.scale)
        let hex = pixelHex(px, py) ?? "-"
        return "\(Int(mouse.x)), \(Int(bounds0.height - mouse.y)) · \(copiedHex == hex ? L("shot.copiedHex") : hex)"
    }

    /// The loupe plus its coordinate pill, for invalidation.
    private func loupeArea() -> CGRect? {
        guard showsLoupe else { return nil }
        let r = loupeRect
        return r.union(pillRect(loupeText, at: CGPoint(x: r.minX, y: r.minY - 26)))
    }

    private func drawLoupe(_ ctx: CGContext) {
        let px = Int((mouse.x) * frozen.scale), py = Int((bounds0.height - mouse.y) * frozen.scale)
        let n = Self.loupeN, zoom = Self.loupeZoom
        let src = CGRect(x: px - n / 2, y: py - n / 2, width: n, height: n)
        guard let crop = frozen.image.cropping(to: src) else { return }
        let r = loupeRect
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
        drawPill(loupeText, at: CGPoint(x: r.minX, y: r.minY - 26), ctx: ctx)
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
        refresh()
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
            refresh(full: true)
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
        refresh()
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
            guard let sel = selection, !CaptureSelection.isClick(sel) else { selection = nil; refresh(); return }
            confirm(sel)
        }
    }

    private func confirm(_ sel: CGRect) {
        let global = sel.offsetBy(dx: frozen.screen.frame.minX, dy: frozen.screen.frame.minY)
        let px = CaptureSelection.pixelRect(global, screen: frozen.screen.frame, scale: frozen.scale)
        guard let crop = frozen.image.cropping(to: px) else { return }
        let screen = frozen.screen
        switch mode {
        case .text: CaptureOverlay.shared.close(); ScreenshotService.shared.finishedText(crop)
        case .scroll: CaptureOverlay.shared.close(); ScrollCapture.shared.start(region: global, screen: screen)
        default:
            // Spinner on the frozen picture first, then the editor opens and only then the frozen screen goes:
            // the click is answered at once instead of a frozen pause (user feedback).
            showBusy(at: sel)
            CATransaction.flush()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                MainActor.assumeIsolated {
                    ScreenshotService.shared.finished(crop)
                    CaptureOverlay.shared.close()
                }
            }
        }
    }

    private func showBusy(at sel: CGRect) {
        let box = NSView(frame: CGRect(x: sel.midX - 32, y: sel.midY - 32, width: 64, height: 64))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        box.layer?.cornerRadius = 14
        let spinner = NSProgressIndicator(frame: CGRect(x: 16, y: 16, width: 32, height: 32))
        spinner.style = .spinning
        spinner.appearance = NSAppearance(named: .darkAqua)
        spinner.usesThreadedAnimation = true   // keeps turning while the main thread builds the editor
        box.addSubview(spinner)
        addSubview(box)
        spinner.startAnimation(nil)
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
        refresh(full: true)
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
            refresh()
            return
        default: break
        }
        guard let ch = e.charactersIgnoringModifiers?.lowercased() else { return }
        if let n = Int(ch), let m = CaptureOverlay.Mode(rawValue: n) { switchMode(m); return }
        if ch == "c", let hex = pixelHex(Int(mouse.x * frozen.scale), Int((bounds0.height - mouse.y) * frozen.scale)) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            copiedHex = hex
            refresh(full: true)
        }
    }
}

/// Transparent drawing layer above the backdrop; mouse events go to CaptureView.
final class OverlayView: NSView {
    /// Layer-hosting backdrop that never takes the click from CaptureView.
    final class PassThrough: NSView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }

    var draw: ((CGContext) -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }
    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        draw?(ctx)
    }
}
