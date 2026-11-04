import AppKit

/// "Pin" (design D40): a capture floating above every window, movable, Esc or double-click closes it.
final class PinWindow: NSPanel {
    private static var open: [PinWindow] = []

    static func pin(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        let rep = image.representations.first
        let scale = (NSScreen.main?.backingScaleFactor ?? 2)
        var size = CGSize(width: CGFloat(rep?.pixelsWide ?? Int(image.size.width)) / scale, height: CGFloat(rep?.pixelsHigh ?? Int(image.size.height)) / scale)
        // Keep it on screen.
        let maxSize = (NSScreen.main?.visibleFrame.size ?? size).applying(CGAffineTransform(scaleX: 0.6, y: 0.6))
        let f = min(1, maxSize.width / size.width, maxSize.height / size.height)
        size = CGSize(width: size.width * f, height: size.height * f)
        let mouse = NSEvent.mouseLocation
        let w = PinWindow(contentRect: CGRect(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2, width: size.width, height: size.height),
                          styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        w.level = .floating
        w.isMovableByWindowBackground = true
        w.hasShadow = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentAspectRatio = size
        let v = NSImageView(image: image)
        v.imageScaling = .scaleProportionallyUpOrDown
        v.wantsLayer = true
        v.layer?.cornerRadius = 6
        v.layer?.masksToBounds = true
        w.contentView = v
        w.orderFrontRegardless()
        open.append(w)
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with e: NSEvent) { if e.keyCode == 53 { close() } else { super.keyDown(with: e) } }

    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 { close(); return }
        super.mouseDown(with: e)
    }

    override func close() {
        super.close()
        Self.open.removeAll { $0 === self }
    }
}
