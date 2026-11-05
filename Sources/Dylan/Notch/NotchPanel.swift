import AppKit
import DylanCore
import SwiftUI

/// Borderless, non-activating panel the size of the largest state. The island is drawn by SwiftUI;
/// mouse events outside the island fall through to the apps below. PRD §2.4, design "Panel & interaksi".
final class NotchPanel: NSPanel {
    var allowKey = false
    override var canBecomeKey: Bool { allowKey }
    override var canBecomeMain: Bool { false }
    /// AppKit pushes windows below the menu bar; the island must sit on the screen's top edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@Observable
final class NotchLayout {
    var geometry: NotchGeometry
    /// Sideways shift while the pill steps out of the cursor's way (D59).
    var dodge: CGFloat = 0
    init(_ g: NotchGeometry) { geometry = g }
}

/// Dragging the pill along the top edge on screens without a notch (FR-113); remembered per screen.
enum PillDrag {
    static func gesture(enabled: Bool) -> some Gesture {
        // The panel moves with the pill, so the drag is measured on the screen, not in the window.
        DragGesture(minimumDistance: 6)
            .onChanged { _ in if enabled { NotchController.shared.dragPill(done: false) } }
            .onEnded { _ in if enabled { NotchController.shared.dragPill(done: true) } }
    }
}

final class NotchController {
    static let shared = NotchController()
    private var panel: NotchPanel?
    private(set) var layout = NotchLayout(NotchController.currentGeometry())
    private var monitors: [Any] = []
    private var hoverWork: DispatchWorkItem?
    private var leaveWork: DispatchWorkItem?
    /// Drag pasteboard count at mouse-down: it keeps the last drag's types, so only a change means a new file drag.
    private var dragStartCount = 0
    private var inside = false
    private var lastState: NotchState = .closed
    /// For the dodge: where and when the cursor was last seen.
    private var lastMouse: (point: CGPoint, at: TimeInterval)?
    private var dodgeWork: DispatchWorkItem?
    private var dragStart: (mouse: CGFloat, offset: CGFloat)?

    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    static func currentGeometry() -> NotchGeometry {
        guard let s = targetScreen() else {
            return NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32, leftAuxWidth: 663.5, rightAuxWidth: 663.5)
        }
        var g = NotchGeometry(screen: s.frame, safeAreaTop: s.safeAreaInsets.top,
                              leftAuxWidth: s.auxiliaryTopLeftArea?.width, rightAuxWidth: s.auxiliaryTopRightArea?.width)
        if AppModel.shared.smallCompact { g.ear = 72 }
        if !g.hasNotch {
            let p = Prefs.shared
            if p.style == .floating { g.pillGap = p.floatGap; g.pillExtraWidth = p.floatWidth }
            let half = NotchGeometry.expandedMax.width / 2 + NotchGeometry.panelMargin
            g.centerX = min(max(s.frame.midX + pillOffset(s), s.frame.minX + half), s.frame.maxX - half)
        }
        return g
    }

    func show() {
        let p = NotchPanel(contentRect: layout.geometry.panelFrame, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Shown to the user, hidden from screen sharing where macOS honours it (verified in T1.12).
        // Debug only: `defaults write io.github.ramdanegie.dylan allowScreenCapture -bool true` to screenshot the notch.
        p.sharingType = AppModel.store.bool(forKey: "allowScreenCapture") ? .readOnly : .none
        let host = NSHostingView(rootView: NotchRootView(layout: layout).environment(\.colorScheme, .dark))
        host.sizingOptions = []
        p.contentView = host
        p.orderFrontRegardless()
        panel = p

        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { e in
            let dragging = e.type == .leftMouseDragged
            MainActor.assumeIsolated {
                NotchController.shared.mouseMoved()
                if dragging { NotchController.shared.fileDragMoved() }
            }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { e in
            MainActor.assumeIsolated { NotchController.shared.mouseMoved() }
            return e
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated {
                NotchController.shared.dragStartCount = NSPasteboard(name: .drag).changeCount
                NotchController.shared.clickedOutside()
            }
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { _ in
            MainActor.assumeIsolated {
                FloatingBasket.shared.dragEnded()
                // Dropped outside every zone: give the island back (a zone's drop clears this itself).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    MainActor.assumeIsolated {
                        let m = AppModel.shared
                        if m.dropping { m.dropping = false; NotchController.shared.collapse() }
                    }
                }
            }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { e in
            if e.keyCode == 53 {   // Esc
                MainActor.assumeIsolated { NotchController.shared.collapse() }
                return nil
            }
            return e
        } as Any)

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotchController.shared.relayout() }
        }
        let wnc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            wnc.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    NotchController.shared.checkFullscreen()
                    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
                    let hide = AppModel.shared.hideForApps.contains(front)
                    if AppModel.shared.hiddenForFrontApp != hide { AppModel.shared.hiddenForFrontApp = hide }
                    // ⌘-Tab away from an open notch closes it, so typing goes to the new app.
                    if AppModel.shared.notchState == .expanded { NotchController.shared.collapse() }
                }
            }
        }
        wnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                NotchController.shared.relayout()
                CalendarProvider.shared.reload()
                RemindersProvider.shared.reload()
                WeatherProvider.shared.refresh()
                AppModel.shared.tick()
            }
        }
        observeModel()
    }

    private static func pillKey(_ s: NSScreen) -> String { "pill.offset." + s.localizedName }
    private static func pillOffset(_ s: NSScreen) -> CGFloat { CGFloat(AppModel.store.double(forKey: pillKey(s))) }

    func dragPill(done: Bool) {
        guard let s = Self.targetScreen(), !layout.geometry.hasNotch else { return }
        let x = NSEvent.mouseLocation.x
        let start = dragStart ?? (x, Self.pillOffset(s))
        dragStart = done ? nil : start
        // Kept within the screen, so a pill dragged off the edge is not lost.
        let half = s.frame.width / 2 - NotchGeometry.expandedMax.width / 2 - NotchGeometry.panelMargin
        AppModel.store.set(Double(min(max(start.offset + x - start.mouse, -half), half)), forKey: Self.pillKey(s))
        relayout()
    }

    func relayout() {
        layout.geometry = Self.currentGeometry()
        panel?.setFrame(layout.geometry.panelFrame, display: true)
    }

    /// Keeps the panel's key status and visibility in sync with the model.
    private func observeModel() {
        withObservationTracking {
            _ = AppModel.shared.notchState
            _ = AppModel.shared.selectedTab
            _ = AppModel.shared.fullscreen
            _ = AppModel.shared.hiddenForFrontApp
            _ = AppModel.shared.center.urgentIDs
        } onChange: {
            Task { @MainActor in
                NotchController.shared.modelChanged()
                NotchController.shared.observeModel()
            }
        }
    }

    private func modelChanged() {
        let m = AppModel.shared
        let hidden = (m.fullscreen || m.hiddenForFrontApp) && m.center.urgentIDs.isEmpty && m.notchState != .expanded
        panel?.alphaValue = hidden ? 0 : 1
        // Take keyboard focus once, when opening; never again on later model changes (FR-3).
        if m.notchState == .expanded && lastState != .expanded {
            panel?.allowKey = true
            panel?.makeKey()
        } else if m.notchState != .expanded && panel?.allowKey == true {
            panel?.allowKey = false
            panel?.resignKey()
        }
        lastState = m.notchState
        StatsProvider.shared.refreshSchedule()
        m.center.setHoldPaused(m.notchState != .closed && inside, now: Date())
        mouseMoved()
    }

    // MARK: Hover (150 ms in, 300 ms out — design M2)

    /// The island's current frame in screen coordinates, a little larger so the edge is easy to hit.
    private func hitFrame() -> CGRect {
        NotchRootView.islandFrame(AppModel.shared, layout.geometry).insetBy(dx: -DY.shoulder, dy: -2)
    }

    private func mouseMoved() {
        guard let panel else { return }
        let m = AppModel.shared
        dodgeIfPassing()
        let now = hitFrame().contains(NSEvent.mouseLocation) && panel.alphaValue > 0
        panel.ignoresMouseEvents = !now
        guard now != inside else { return }
        inside = now
        m.center.setHoldPaused(now, now: Date())
        if now {
            leaveWork?.cancel()
            guard m.notchState == .closed || m.notchState == .compact, !m.center.slots().isEmpty else { return }
            let w = DispatchWorkItem { MainActor.assumeIsolated {
                let m = AppModel.shared
                if NotchController.shared.inside, m.notchState != .expanded { m.notchState = .peek }
            } }
            hoverWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + m.hoverDelay, execute: w)
        } else {
            hoverWork?.cancel()
            let w = DispatchWorkItem { MainActor.assumeIsolated {
                if !NotchController.shared.inside { NotchController.shared.collapse() }
            } }
            leaveWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
        }
    }

    /// A file dragged close to the notch opens the Shelf as a drop zone (PRD §F1).
    private func fileDragMoved() {
        let m = AppModel.shared
        let pb = NSPasteboard(name: .drag)
        guard m.features.isEnabled(.shelf), m.notchState != .expanded, pb.changeCount != dragStartCount,
              let types = pb.types, types.contains(.fileURL) else { return }
        let zone = NotchRootView.islandFrame(m, layout.geometry).insetBy(dx: -80, dy: -60)
        guard zone.contains(NSEvent.mouseLocation) else { FloatingBasket.shared.dragMoved(at: NSEvent.mouseLocation); return }
        m.dropping = true
        m.notchState = .expanded
    }

    private func clickedOutside() {
        if AppModel.shared.notchState == .expanded && !hitFrame().contains(NSEvent.mouseLocation) { collapse() }
    }

    /// Share… from the drop zones (D56), anchored under the island.
    func share(_ urls: [URL]) {
        guard let view = panel?.contentView else { return }
        let f = NotchRootView.islandFrame(AppModel.shared, layout.geometry)
        let local = view.convert(panel!.convertFromScreen(f), from: nil)
        NSSharingServicePicker(items: urls).show(relativeTo: local, of: view, preferredEdge: .minY)
    }

    /// D59: on screens without a notch the pill steps 180 pt aside when the cursor only passes by (faster than
    /// it would move to stop on it), and comes back once the cursor has gone.
    private func dodgeIfPassing() {
        let p = NSEvent.mouseLocation, now = ProcessInfo.processInfo.systemUptime
        defer { lastMouse = (p, now) }
        let m = AppModel.shared
        guard Prefs.shared.dodgeMouse, !layout.geometry.hasNotch, m.notchState == .closed || m.notchState == .compact else { return }
        var home = NotchRootView.islandFrame(m, layout.geometry)
        home.origin.x -= layout.dodge
        if layout.dodge != 0 {
            guard !home.insetBy(dx: -30, dy: -20).contains(p), dodgeWork == nil else { return }
            let w = DispatchWorkItem { MainActor.assumeIsolated { NotchController.shared.layout.dodge = 0; NotchController.shared.dodgeWork = nil } }
            dodgeWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
            return
        }
        guard home.contains(p), let last = lastMouse, now > last.at else { return }
        let speed = hypot(p.x - last.point.x, p.y - last.point.y) / (now - last.at)
        // ~150 ms to cross: a cursor at this speed is on its way somewhere else.
        guard speed > home.width / 0.15 * 0.5 else { return }
        dodgeWork?.cancel(); dodgeWork = nil
        layout.dodge = p.x < home.midX ? 180 : -180
    }

    func collapse() {
        let m = AppModel.shared
        m.dropping = false
        if m.autoPeekUntil != nil && m.notchState == .peek { return }   // P0 auto-peek stays 4 s
        m.notchState = m.center.slots().isEmpty ? .closed : .compact
    }

    // MARK: Fullscreen (FR-5): frontmost app has a window covering the whole screen.

    func checkFullscreen() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let screen = Self.targetScreen(),
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return }
        let size = screen.frame.size
        // On notched Macs fullscreen content sits below the camera housing: height = screen − safe area.
        let minHeight = size.height - screen.safeAreaInsets.top
        let isFullscreen = list.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid, (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return b["Width"] == size.width && (b["Height"] ?? 0) >= minHeight
        }
        if AppModel.shared.fullscreen != isFullscreen { AppModel.shared.fullscreen = isFullscreen }
    }
}
