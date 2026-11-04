import Carbon.HIToolbox
import Foundation

/// Global hotkeys through Carbon `RegisterEventHotKey` (no Accessibility permission needed).
/// ⌃⌥Space opens the notch, ⌃⌥⌘H toggles Presentation Mode.
enum Hotkeys {
    nonisolated(unsafe) private static var handlers: [UInt32: () -> Void] = [:]
    nonisolated(unsafe) private static var refs: [UInt32: EventHotKeyRef] = [:]
    nonisolated(unsafe) private static var installed = false

    static func register(id: UInt32, keyCode: Int, modifiers: Int, _ handler: @escaping () -> Void) {
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                MainActor.assumeIsolated { Hotkeys.handlers[hk.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
            installed = true
        }
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x44594C4E), id: id)   // 'DYLN'
        if RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
            refs[id] = ref
        }
    }

    /// Screenshot shortcuts (FR-88, D38): ⌥⇧ so they never clash with macOS's ⇧⌘3/4/5. Registered only while the
    /// feature is on, so the keys reach other apps otherwise.
    static func setScreenshotKeys(_ on: Bool) {
        let shots: [(UInt32, Int, CaptureOverlay.Mode?)] = [(10, kVK_ANSI_1, .area), (11, kVK_ANSI_2, .window), (12, kVK_ANSI_3, .screen),
                                                             (13, kVK_ANSI_4, .scroll), (14, kVK_ANSI_T, .text), (15, kVK_ANSI_E, nil)]
        for (id, key, mode) in shots {
            unregister(id: id)
            if on {
                register(id: id, keyCode: key, modifiers: optionKey | shiftKey) {
                    if let mode { CaptureOverlay.shared.start(mode) } else { ScreenshotService.shared.openLast() }
                }
            }
        }
        setTakeOver(on && AppModel.store.bool(forKey: "shot.takeOver"))
    }

    static func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }

    /// "Take over ⇧⌘3/4/5" (D43). macOS handles its own shortcuts first, so they only reach Dylan once they are
    /// turned off in System Settings → Keyboard → Keyboard Shortcuts → Screenshots.
    static func setTakeOver(_ on: Bool) {
        let keys: [(UInt32, Int, CaptureOverlay.Mode)] = [(20, kVK_ANSI_3, .screen), (21, kVK_ANSI_4, .area), (22, kVK_ANSI_5, .area)]
        for (id, key, mode) in keys {
            unregister(id: id)
            if on { register(id: id, keyCode: key, modifiers: cmdKey | shiftKey) { CaptureOverlay.shared.start(mode) } }
        }
    }

    static func registerDefaults() {
        register(id: 1, keyCode: kVK_Space, modifiers: controlKey | optionKey) {
            let m = AppModel.shared
            m.notchState = m.notchState == .expanded ? .closed : .expanded
        }
        register(id: 2, keyCode: kVK_ANSI_H, modifiers: controlKey | optionKey | cmdKey) {
            AppModel.shared.togglePresentation()
        }
        register(id: 3, keyCode: kVK_ANSI_C, modifiers: controlKey | optionKey) {
            AppModel.shared.pickColor()
        }
        register(id: 4, keyCode: kVK_ANSI_V, modifiers: controlKey | optionKey) {
            AppModel.shared.openClipboard()
        }
        // Quick terminal (FR-41): drops down from the notch, again to put it away.
        register(id: 5, keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey) {
            let m = AppModel.shared
            guard m.tabs.contains(.terminal) else { return }
            if m.notchState == .expanded && m.selectedTab == .terminal { m.notchState = .closed; return }
            m.selectedTab = .terminal
            m.notchState = .expanded
        }
    }
}
