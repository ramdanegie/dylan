import AppKit
import DylanCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // One Dylan at a time: a second copy would take over the socket and draw a second island.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
            NSApp.terminate(nil)
            return
        }
        NotchController.shared.show()
        SocketServer.shared.start()
        Hotkeys.registerDefaults()
        installMenuBar()
        refreshProviders()
        observeProviders()

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                AppModel.shared.screenLocked = true
                // Never hold a prompt while nobody can answer it.
                for id in AppModel.shared.pending.keys { AppModel.shared.resolvePermission(id, .passthrough) }
            }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppModel.shared.screenLocked = false }
        }
        if !AppModel.shared.onboardingDone { OnboardingWindow.show() }
        // `--open-notch <tab>`: opens Expanded on a tab (screenshots and quick checks).
        if let i = CommandLine.arguments.firstIndex(of: "--open-notch"), i + 1 < CommandLine.arguments.count,
           let tab = Tab(rawValue: CommandLine.arguments[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                AppModel.shared.selectedTab = tab
                AppModel.shared.notchState = .expanded
            }
        }
        // `--open-settings <section>` (e.g. features): used for screenshots and quick checks.
        if let i = CommandLine.arguments.firstIndex(of: "--open-settings"), i + 1 < CommandLine.arguments.count,
           let section = SettingsSection(rawValue: CommandLine.arguments[i + 1]) {
            SettingsWindow.show(section: section)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stopKeepAwake()
        if AppModel.shared.clearClipboardOnQuit { ClipboardProvider.shared.clearAll() }
        for id in AppModel.shared.pending.keys { AppModel.shared.resolvePermission(id, .passthrough) }
        SocketServer.shared.stop()
    }

    /// Start or stop providers to match the feature toggles (disabled features cost nothing).
    func refreshProviders() {
        let f = AppModel.shared.features
        f.isEnabled(.media) ? MediaProvider.shared.start() : MediaProvider.shared.stop()
        f.isEnabled(.media) && f.isEnabled(.otherPlayers) ? OtherPlayersProvider.shared.start() : OtherPlayersProvider.shared.stop()
        f.isEnabled(.meeting) ? CalendarProvider.shared.start(requestAccess: false) : CalendarProvider.shared.stop()
        f.isEnabled(.battery) ? BatteryProvider.shared.start() : BatteryProvider.shared.stop()
        f.isEnabled(.bluetooth) ? BluetoothProvider.shared.start() : BluetoothProvider.shared.stop()
        f.isEnabled(.privacy) ? PrivacyProvider.shared.start() : ()
        f.isEnabled(.clipboard) ? ClipboardProvider.shared.start() : ClipboardProvider.shared.stop()
        StatsProvider.shared.refreshSchedule()
        f.isEnabled(.ports) ? PortsProvider.shared.start() : PortsProvider.shared.stop()
        f.isEnabled(.shelf) ? ShelfProvider.shared.start() : ShelfProvider.shared.stop()
        f.isEnabled(.reminders) ? RemindersProvider.shared.start(requestAccess: false) : RemindersProvider.shared.stop()
        f.isEnabled(.weather) ? WeatherProvider.shared.start() : WeatherProvider.shared.stop()
        f.isEnabled(.downloads) ? DownloadsProvider.shared.start() : DownloadsProvider.shared.stop()
        f.isEnabled(.github) ? DevIntegrations.shared.startGitHub() : DevIntegrations.shared.stopGitHub()
        f.isEnabled(.widgets) ? DevIntegrations.shared.startWidgets() : DevIntegrations.shared.stopWidgets()
        f.isEnabled(.discord) ? DiscordProvider.shared.start() : DiscordProvider.shared.stop()
        f.isEnabled(.hud) ? HUDProvider.shared.start() : HUDProvider.shared.stop()
        f.isEnabled(.focus) ? FocusProvider.shared.start() : FocusProvider.shared.stop()
        if !f.isEnabled(.meeting) { MeetingCallProvider.shared.end() }
        VisualizerProvider.shared.update()
        if !f.isEnabled(.appVolume) { AppVolumeProvider.shared.stopAll() }
        f.isEnabled(.notifications) ? NotificationProvider.shared.start() : NotificationProvider.shared.stop()
        if !f.isEnabled(.terminal) { TerminalProvider.shared.stop() }
        f.isEnabled(.lockScreen) ? LockScreenProvider.shared.start() : LockScreenProvider.shared.stop()
        FaceUnlockProvider.shared.start()
        f.isEnabled(.timeToLeave) && f.isEnabled(.meeting) ? TravelProvider.shared.start() : TravelProvider.shared.stop()
        PrivacyProvider.shared.update()
        // A tab that was just turned off must not keep rendering.
        if !AppModel.shared.tabs.contains(AppModel.shared.selectedTab) { AppModel.shared.selectedTab = .home }
        if !f.isEnabled(.agents) {
            for id in AppModel.shared.pending.keys { AppModel.shared.resolvePermission(id, .passthrough) }
            AppModel.shared.center.remove("agents", now: Date())
        }
        statusItem?.menu = makeMenu()
    }

    private func observeProviders() {
        withObservationTracking { _ = AppModel.shared.providersNeedRefresh } onChange: {
            Task { @MainActor in
                (NSApp.delegate as? AppDelegate)?.refreshProviders()
                (NSApp.delegate as? AppDelegate)?.observeProviders()
            }
        }
    }

    // MARK: Menu bar (D17)

    private func installMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarIcon()
        item.button?.setAccessibilityLabel("Dylan")
        item.menu = makeMenu()
        statusItem = item
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let count = AppModel.shared.center.activities.values.filter { $0.state == .running }.count
        let header = NSMenuItem(title: count == 0 ? "Dylan" : L("menu.running", count), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        let open = NSMenuItem(title: L("menu.open"), action: #selector(openNotch), keyEquivalent: " ")
        open.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(open)
        let pres = NSMenuItem(title: L("menu.presentation"), action: #selector(togglePresentation), keyEquivalent: "h")
        pres.keyEquivalentModifierMask = [.control, .option, .command]
        pres.state = AppModel.shared.presentationMode ? .on : .off
        menu.addItem(pres)
        if AppModel.shared.features.isEnabled(.screenshot) {
            let shot = NSMenuItem(title: L("shot.menu"), action: nil, keyEquivalent: "")
            shot.submenu = makeScreenshotMenu()
            menu.addItem(shot)
        }
        let awake = NSMenuItem(title: L("keepAwake.button"), action: #selector(toggleKeepAwake), keyEquivalent: "")
        awake.state = AppModel.shared.keepAwake != nil ? .on : .off
        menu.addItem(awake)
        // FR-55: one click to turn Face Unlock off.
        if FaceUnlockProvider.shared.enabled {
            menu.addItem(NSMenuItem(title: L("faceUnlock.turnOff"), action: #selector(disableFaceUnlock), keyEquivalent: ""))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("menu.settings"), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for i in menu.items where i.action != #selector(NSApplication.terminate(_:)) { i.target = self }
        return menu
    }

    @objc private func openNotch() { AppModel.shared.notchState = .expanded }
    @objc private func togglePresentation() { AppModel.shared.togglePresentation() }
    @objc private func toggleKeepAwake() { AppModel.shared.toggleKeepAwake() }

    // MARK: Screenshot menu (design D38)

    private func makeScreenshotMenu() -> NSMenu {
        let m = NSMenu()
        func item(_ key: String, _ action: Selector, _ eq: String = "", _ mods: NSEvent.ModifierFlags = [.option, .shift], tag: Int = 0) -> NSMenuItem {
            let i = NSMenuItem(title: L(key), action: action, keyEquivalent: eq)
            i.keyEquivalentModifierMask = mods
            i.target = self
            i.tag = tag
            return i
        }
        m.addItem(item("shot.captureArea", #selector(captureMode(_:)), "1", tag: 1))
        m.addItem(item("shot.captureWindow", #selector(captureMode(_:)), "2", tag: 2))
        m.addItem(item("shot.captureScreen", #selector(captureMode(_:)), "3", tag: 3))
        m.addItem(item("shot.captureScroll", #selector(captureMode(_:)), "4", tag: 4))
        m.addItem(item("shot.captureText", #selector(captureMode(_:)), "t", tag: 5))
        let timer = NSMenuItem(title: L("shot.captureTimer"), action: nil, keyEquivalent: "")
        let tm = NSMenu()
        for s in [3, 5, 10] {
            let i = item("shot.seconds", #selector(captureTimer(_:)), tag: s)
            i.title = L("shot.seconds", s)
            tm.addItem(i)
        }
        timer.submenu = tm
        m.addItem(timer)
        let rec = NSMenuItem(title: L("shot.record"), action: nil, keyEquivalent: "")
        rec.isEnabled = false
        m.addItem(rec)
        m.addItem(.separator())
        m.addItem(item("shot.pickColor", #selector(pickColorFromMenu), "c", [.control, .option]))
        m.addItem(item("shot.openLast", #selector(openLastCapture), "e"))
        m.addItem(item("shot.history", #selector(openCaptureHistory)))
        return m
    }

    @objc private func captureMode(_ sender: NSMenuItem) {
        guard let mode = CaptureOverlay.Mode(rawValue: sender.tag) else { return }
        // Let the menu close before the screen is frozen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { MainActor.assumeIsolated { CaptureOverlay.shared.start(mode) } }
    }

    @objc private func captureTimer(_ sender: NSMenuItem) { CaptureOverlay.shared.start(.area, delay: sender.tag) }
    @objc private func pickColorFromMenu() { AppModel.shared.pickColor() }
    @objc private func openLastCapture() { ScreenshotService.shared.openLast() }
    @objc private func openCaptureHistory() { CaptureHistoryWindow.show() }
    @objc private func disableFaceUnlock() { FaceUnlockProvider.shared.disable(); statusItem?.menu = makeMenu() }
    @objc private func openSettings() { SettingsWindow.show() }

    /// Template icon: black capsule = island, knocked-out dot = status (design §3).
    static func menuBarIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            let capsule = NSBezierPath(roundedRect: NSRect(x: 2, y: 6, width: 14, height: 6.5), xRadius: 3.25, yRadius: 3.25)
            capsule.append(NSBezierPath(ovalIn: NSRect(x: 11, y: 7.75, width: 3, height: 3)).reversed)
            NSColor.black.setFill()
            capsule.fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let fresh = makeMenu()
        menu.removeAllItems()
        for item in fresh.items { fresh.removeItem(item); menu.addItem(item) }
    }
}

// MARK: Entry point

let arguments = CommandLine.arguments
if let i = arguments.firstIndex(of: "--snapshot"), i + 1 < arguments.count {
    if let l = arguments.firstIndex(of: "--lang"), l + 1 < arguments.count { L10n.forcedLanguage = arguments[l + 1] }
    Snapshot.render(to: URL(fileURLWithPath: arguments[i + 1]))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
