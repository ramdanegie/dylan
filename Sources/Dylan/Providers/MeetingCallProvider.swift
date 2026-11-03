import AppKit
import ApplicationServices
import DylanCore

/// The call in progress and its controls (FR-83, design D28): Zoom, Teams or Google Meet, detected from
/// the app using the microphone. Needs Accessibility (asked on first use) to press menu items / send shortcuts.
final class MeetingCallProvider {
    static let shared = MeetingCallProvider()
    private(set) var app: MeetingControls.App?
    private var pid: pid_t = 0
    private var expiry: DispatchWorkItem?
    private var shareTimer: Timer?
    /// Presentation Mode that Dylan turned on for a share; turned off again when the share ends.
    private var autoPresenting = false
    /// The user turned Presentation Mode off during this share: do not turn it back on.
    private var overridden = false
    /// The call's mic went quiet, but a share was still on; finish once it stops.
    private var callEnded = false

    /// Called whenever the microphone user changes (PrivacyProvider.update).
    func micChanged() {
        let m = AppModel.shared
        guard m.features.isEnabled(.meeting) else { end(); return }
        if let p = m.micAppProcess,
           let a = MeetingControls.app(bundleID: p.bundleID, windowTitle: Self.focusedWindowTitle(p.pid)) {
            expiry?.cancel(); expiry = nil
            callEnded = false
            app = a; pid = p.pid
            publish()
            watchSharing()
        } else if app != nil, expiry == nil {
            // Muting can stop the microphone; keep the controls a little longer.
            let w = DispatchWorkItem { MainActor.assumeIsolated { MeetingCallProvider.shared.end() } }
            expiry = w
            DispatchQueue.main.asyncAfter(deadline: .now() + MeetingControls.grace, execute: w)
        }
    }

    func end() {
        expiry?.cancel(); expiry = nil
        // Muted for a while during a screen share: keep Presentation Mode (and the share check) until the share ends.
        if autoPresenting, let app, pid > 0, AppModel.shared.features.isEnabled(.meeting),
           MeetingControls.isSharing(app, windowTitles: Self.windowTitles(pid)) {
            callEnded = true
            AppModel.shared.removeIfPresent("meeting-live", now: Date())
            return
        }
        callEnded = false
        shareTimer?.invalidate(); shareTimer = nil
        if autoPresenting { autoPresenting = false; if AppModel.shared.presentationMode { AppModel.shared.togglePresentation() } }
        app = nil; pid = 0
        AppModel.shared.removeIfPresent("meeting-live", now: Date())
    }

    // MARK: Screen sharing → Presentation Mode (FR-28)

    private func watchSharing() {
        guard shareTimer == nil, AppModel.shared.features.isEnabled(.autoPresentation) else { return }
        let t = Timer(timeInterval: MeetingControls.shareCheckInterval, repeats: true) { _ in
            MainActor.assumeIsolated { MeetingCallProvider.shared.checkSharing() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        shareTimer = t
    }

    private func checkSharing() {
        let m = AppModel.shared
        guard let app, pid > 0, m.features.isEnabled(.autoPresentation), AXIsProcessTrusted() else { return }
        let sharing = MeetingControls.isSharing(app, windowTitles: Self.windowTitles(pid))
        if !sharing {
            overridden = false
            if autoPresenting { autoPresenting = false; if m.presentationMode { m.togglePresentation() } }
            if callEnded { end() }
            return
        }
        if autoPresenting, !m.presentationMode { autoPresenting = false; overridden = true }
        if !m.presentationMode, !overridden { autoPresenting = true; m.togglePresentation() }
    }

    static func windowTitles(_ pid: pid_t) -> [String] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &v) == .success,
              let wins = v as? [AXUIElement] else { return [] }
        return wins.compactMap { w in
            var t: CFTypeRef?
            return AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t) == .success ? t as? String : nil
        }
    }

    private func publish() {
        guard let app else { return }
        let m = AppModel.shared
        let now = Date()
        let event = m.meetings.first { !$0.isAllDay && $0.start <= now.addingTimeInterval(5 * 60) && $0.end > now }
        let old = m.center.activities["meeting-live"]
        var a = Activity(id: "meeting-live", kind: .meeting, priority: .p2, state: .running, symbol: "video.fill",
                         label: app.name, value: "", detail: event.map { "\(app.name) · \($0.title)" } ?? L("meetingControls.inCall", app.name),
                         genericDetail: L("generic.meeting"), startedAt: old?.startedAt ?? now, updatedAt: old?.updatedAt ?? now)
        if old != a { a.updatedAt = now; m.center.upsert(a); m.scheduleTick() }
    }

    func press(_ c: MeetingControls.Control) {
        guard let app, pid > 0, let sc = MeetingControls.shortcut(app, c) else { return }
        // First use: macOS shows the Accessibility prompt; nothing is sent until it is granted.
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else { return }
        if app == .meet {
            // Meet lives in a browser whose ⌘D is "Bookmark", and keys go to the front tab: only send when that is Meet.
            guard MeetingControls.app(bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                                      windowTitle: Self.focusedWindowTitle(pid)) == .meet else { return }
        } else if Self.pressMenuItem(pid: pid, key: sc.key, modifiers: sc.axModifiers) {
            // A menu item works while the app is in the background and in any language; else the shortcut.
            return
        }
        guard let code = KeyCodes.letters[sc.key] else { return }
        var flags: CGEventFlags = [.maskCommand]
        if sc.shift { flags.insert(.maskShift) }
        if sc.option { flags.insert(.maskAlternate) }
        if sc.control { flags.insert(.maskControl) }
        let src = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.postToPid(pid)
        }
    }

    // MARK: Accessibility helpers

    static func focusedWindowTitle(_ pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        guard let win = element(app, kAXFocusedWindowAttribute) else { return nil }
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &v) == .success ? v as? String : nil
    }

    /// Finds an enabled menu item whose shortcut is ⌘+`modifiers`+`key` and presses it.
    static func pressMenuItem(pid: pid_t, key: Character, modifiers: Int) -> Bool {
        guard let bar = element(AXUIElementCreateApplication(pid), kAXMenuBarAttribute) else { return false }
        func search(_ el: AXUIElement, depth: Int) -> Bool {
            guard depth < 4 else { return false }
            for child in children(el) {
                var ch: CFTypeRef?, mods: CFTypeRef?, enabled: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXMenuItemCmdCharAttribute as CFString, &ch) == .success,
                   (ch as? String)?.uppercased() == String(key),
                   AXUIElementCopyAttributeValue(child, kAXMenuItemCmdModifiersAttribute as CFString, &mods) == .success,
                   (mods as? Int) == modifiers,
                   AXUIElementCopyAttributeValue(child, kAXEnabledAttribute as CFString, &enabled) == .success, enabled as? Bool == true {
                    return AXUIElementPerformAction(child, kAXPressAction as CFString) == .success
                }
                if search(child, depth: depth + 1) { return true }
            }
            return false
        }
        return search(bar, depth: 0)
    }

    private static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v) == .success else { return [] }
        return (v as? [AXUIElement]) ?? []
    }
}
