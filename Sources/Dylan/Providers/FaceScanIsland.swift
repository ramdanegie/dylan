import AppKit
import DylanCore
import SwiftUI

/// The scan island on the lock screen (FR-118, after Glance): which move to make, right under the camera, then
/// a tick or a cross. Only a private SkyLight space can show a window there, as for the lock-screen widgets
/// (FR-80); when macOS refuses, `show` returns false and the challenge is spoken instead.
@Observable
final class FaceScanIsland {
    enum Phase: Equatable {
        case scanning(step: String, index: Int, count: Int)
        case passed
        case failed(String)
    }

    static let shared = FaceScanIsland()
    var phase: Phase = .passed
    var spaceHint = false
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var space: Int32 = 0
    @ObservationIgnored private var unavailable = false
    @ObservationIgnored private var hideWork: DispatchWorkItem?

    /// true when the island is up (now or already).
    @discardableResult
    func show(_ p: Phase, hideAfter: TimeInterval? = nil) -> Bool {
        // Never over an unlocked desktop (a late step change or timeout after a Touch ID unlock).
        guard FaceUnlockProvider.screenLocked else { hide(); return false }
        phase = p
        hideWork?.cancel(); hideWork = nil
        if let hideAfter {
            let w = DispatchWorkItem { MainActor.assumeIsolated { FaceScanIsland.shared.hide() } }
            hideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + hideAfter, execute: w)
        }
        if panel != nil { return true }
        // The built-in screen, where the camera is.
        guard !unavailable, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return false }
        let notch = screen.safeAreaInsets.top
        let size = NSSize(width: FaceScanCard.width, height: FaceScanCard.height(notch: notch))
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: FaceScanLive(notch: notch).environment(\.colorScheme, .dark))
        p.orderFrontRegardless()
        guard let s = SkyLight.moveToLockScreen(windowNumber: p.windowNumber) else {
            unavailable = true   // not this run again
            p.close()
            return false
        }
        space = s
        panel = p
        return true
    }

    func hide() {
        hideWork?.cancel(); hideWork = nil
        if space != 0 { SkyLight.destroy(space: space); space = 0 }
        panel?.close()
        panel = nil
    }
}

private struct FaceScanLive: View {
    var notch: CGFloat
    private var island: FaceScanIsland { .shared }
    var body: some View { FaceScanCard(phase: island.phase, spaceHint: island.spaceHint, notch: notch) }
}

/// The island itself, hanging from the notch (or a pill on screens without one). Also drawn by `--snapshot`.
struct FaceScanCard: View {
    var phase: FaceScanIsland.Phase
    var spaceHint: Bool
    var notch: CGFloat

    static let width: CGFloat = 330
    static func height(notch: CGFloat) -> CGFloat { notch + 56 }

    var body: some View {
        HStack(spacing: 12) {
            icon.font(.system(size: 22, weight: .medium)).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                SwiftUI.Text(title).font(DY.font(14, .semibold)).foregroundStyle(DY.fg).lineLimit(1)
                SwiftUI.Text(subtitle).font(DY.font(11.5)).foregroundStyle(DY.fg2).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, notch > 0 ? 30 : 16)
        .padding(.top, notch > 0 ? notch : 0)
        .frame(width: Self.width, height: Self.height(notch: notch) - (notch > 0 ? 0 : 8))
        .background {
            if notch > 0 { NotchShape(bottomRadius: 22).fill(Color.black) } else { PillShape(radius: 22).fill(Color.black) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, notch > 0 ? 0 : 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var icon: some View {
        switch phase {
        case .scanning:
            Image(systemName: "faceid").foregroundStyle(Color(nsColor: Art.hex(0x66D4CF)))
                .symbolEffect(.pulse, options: .repeating, isActive: Prefs.motionAllowed)
        case .passed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private var title: String {
        switch phase {
        case .scanning(let step, _, _): return step.prefix(1).uppercased() + step.dropFirst()
        case .passed: return L("faceUnlock.scan.passed")
        case .failed: return L("faceUnlock.scan.failed")
        }
    }

    private var subtitle: String {
        switch phase {
        case .scanning(_, let i, let n): return L("faceUnlock.scan.step", i, n)
        case .passed: return L("faceUnlock.scan.opening")
        case .failed(let why): return spaceHint ? L("faceUnlock.scan.retry", why) : why
        }
    }
}
