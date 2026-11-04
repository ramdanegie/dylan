import AppKit
import DylanCore
import SwiftUI

/// Floating basket (FR-86): shake the pointer while dragging files and a small drop target appears next
/// to it, so external displays far from the notch can still reach the shelf.
final class FloatingBasket {
    static let shared = FloatingBasket()
    private var panel: NSPanel?
    private var shake = ShakeDetector()
    private var hideWork: DispatchWorkItem?

    func dragMoved(at point: NSPoint) {
        guard AppModel.shared.features.isEnabled(.shelf), panel == nil else { return }
        if shake.feed(x: point.x, time: ProcessInfo.processInfo.systemUptime) { show(near: point) }
    }

    func dragEnded() { shake.reset() }

    private func show(near p: NSPoint) {
        let size = NSSize(width: 170, height: 110)
        let frame = NSRect(x: p.x + 24, y: p.y - size.height / 2, width: size.width, height: size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: BasketView().environment(\.colorScheme, .dark))
        panel.orderFrontRegardless()
        self.panel = panel
        scheduleHide(after: 5)
    }

    func dropped() { scheduleHide(after: 0.4) }

    private func scheduleHide(after s: TimeInterval) {
        hideWork?.cancel()
        let w = DispatchWorkItem { MainActor.assumeIsolated {
            let b = FloatingBasket.shared
            // Keep it while a drag is still going on.
            if NSEvent.pressedMouseButtons != 0 { b.scheduleHide(after: 1); return }
            b.panel?.orderOut(nil); b.panel = nil; b.shake.reset()
        } }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: w)
    }
}

private struct BasketView: View {
    @StateBox private var targeted = false
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "basket.fill").font(.system(size: 22)).foregroundStyle(.white)
            SwiftUI.Text(L("basket.drop")).font(DY.font(12, .semibold)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(targeted ? Color.white : Color.white.opacity(0.3)).padding(6))
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { @Sendable url, _ in
                    guard let url else { return }
                    Task { @MainActor in ShelfProvider.shared.add([url]); FloatingBasket.shared.dropped() }
                }
            }
            return true
        }
    }
}
