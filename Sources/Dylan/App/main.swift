import AppKit
import AVFoundation
import DylanCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private struct IconLook: Equatable { var state: MenuBarState; var dot: Bool }
    private var iconLook: IconLook?

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
        ScreenshotService.shared.pruneHistory()   // retention also applies when nothing new is captured
        QuickToggles.shared.recoverAtLaunch()
        installMenuBar()
        refreshProviders()
        observeProviders()
        observeStatusIcon()
        UpdateService.shared.launched()   // What's New after an update; daily check only if turned on

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

    /// Quitting mid-recording would leave an unreadable MP4: finish the file first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ScreenRecorder.shared.isBusy else { return .terminateNow }
        ScreenRecorder.shared.stop { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stopKeepAwake()
        QuickToggles.shared.restore()
        PrayerProvider.shared.stopAdhan()
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
        Hotkeys.setScreenshotKeys(f.isEnabled(.screenshot))
        f.isEnabled(.thermal) ? FanProvider.shared.start() : FanProvider.shared.stop()
        Hotkeys.setFanKeys(f.isEnabled(.thermal) && FanProvider.shared.hasFans)
        f.isEnabled(.storage) ? StorageProvider.shared.start() : StorageProvider.shared.stop()
        f.isEnabled(.prayer) ? PrayerProvider.shared.start() : PrayerProvider.shared.stop()
        Hotkeys.setQuickKeys(f.isEnabled(.quickToggles))
        if !f.isEnabled(.quickToggles) { QuickToggles.shared.restore() }
        refreshStatusItem()
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

    /// The menu bar icon follows the notch: idle, running, needs you, Presentation Mode.
    private func observeStatusIcon() {
        withObservationTracking { _ = Self.menuBarState() } onChange: {
            Task { @MainActor in
                (NSApp.delegate as? AppDelegate)?.refreshStatusItem()
                (NSApp.delegate as? AppDelegate)?.observeStatusIcon()
            }
        }
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
        item.button?.image = Self.menuBarIcon(Self.menuBarState())
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
        if AppModel.shared.features.isEnabled(.thermal) && FanProvider.shared.hasFans {
            let fan = NSMenuItem(title: L("fan.menu"), action: nil, keyEquivalent: "")
            fan.submenu = makeFanMenu()
            menu.addItem(fan)
        }
        let awake = NSMenuItem(title: L("keepAwake.button"), action: #selector(toggleKeepAwake), keyEquivalent: "")
        awake.state = AppModel.shared.keepAwake != nil ? .on : .off
        menu.addItem(awake)
        // FR-55: one click to turn Face Unlock off.
        if FaceUnlockProvider.shared.enabled {
            menu.addItem(NSMenuItem(title: L("faceUnlock.turnOff"), action: #selector(disableFaceUnlock), keyEquivalent: ""))
        }
        menu.addItem(.separator())
        if AppModel.shared.features.isEnabled(.storage) {
            menu.addItem(NSMenuItem(title: L("storage.menu"), action: #selector(openStorage), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem(title: L("about.menu"), action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L("update.check"), action: #selector(checkForUpdates), keyEquivalent: ""))
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
        m.addItem(item(ScreenRecorder.shared.isRecording ? "rec.stop" : "shot.record", #selector(toggleRecording), "5"))
        m.addItem(.separator())
        m.addItem(item("shot.pickColor", #selector(pickColorFromMenu), "c", [.control, .option]))
        m.addItem(item("shot.openLast", #selector(openLastCapture), "e"))
        m.addItem(item("shot.history", #selector(openCaptureHistory)))
        return m
    }

    /// Fan ▸ (design D46): temperatures, the presets with ⌃⌥⇧0–4, and Settings.
    private func makeFanMenu() -> NSMenu {
        let p = FanProvider.shared, m = NSMenu()
        func info(_ s: String) { let i = NSMenuItem(title: s, action: nil, keyEquivalent: ""); i.isEnabled = false; m.addItem(i) }
        info("CPU \(p.format(p.cpu)) · GPU \(p.format(p.temps[.gpu]))")
        info(p.fans.map { "\(FanProvider.fanName($0.index, of: p.fans.count)) \(FanProvider.rpm($0.rpm))" }.joined(separator: " · "))
        m.addItem(.separator())
        for (n, preset) in FanPreset.allCases.enumerated() {
            let shortcut = FanPreset.shortcuts.firstIndex(of: preset).map(String.init) ?? ""
            let i = NSMenuItem(title: L("fan.menu.\(preset.rawValue)"), action: #selector(pickFanPreset(_:)), keyEquivalent: shortcut)
            i.keyEquivalentModifierMask = [.control, .option, .shift]
            i.tag = n
            i.target = self
            i.state = p.preset == preset ? .on : .off
            m.addItem(i)
        }
        m.addItem(.separator())
        let s = NSMenuItem(title: L("fan.settings"), action: #selector(openFanSettings), keyEquivalent: "")
        s.target = self
        m.addItem(s)
        return m
    }

    @objc private func showAbout() { About.showPanel() }
    @objc private func openStorage() { StorageWindow.show() }
    @objc private func checkForUpdates() { UpdateService.shared.check(manual: true); UpdateWindow.show() }
    @objc private func pickFanPreset(_ sender: NSMenuItem) { FanProvider.shared.setPreset(FanPreset.allCases[sender.tag]) }
    @objc private func openFanSettings() { SettingsWindow.show(section: .thermal) }

    /// Dot when Dylan drives the fans, so manual mode is not forgotten; optional CPU temperature (D46).
    func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        let p = FanProvider.shared, on = AppModel.shared.features.isEnabled(.thermal)
        let look = IconLook(state: Self.menuBarState(), dot: on && p.preset != .auto)
        if look != iconLook { iconLook = look; button.image = Self.menuBarIcon(look.state, dot: look.dot) }
        let title = on && p.menuTemp ? p.format(p.cpu) : ""
        if button.title != title {
            button.title = title
            button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
            statusItem?.length = title.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
        }
    }

    @objc private func captureMode(_ sender: NSMenuItem) {
        guard let mode = CaptureOverlay.Mode(rawValue: sender.tag) else { return }
        // Let the menu close before the screen is frozen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { MainActor.assumeIsolated { CaptureOverlay.shared.start(mode) } }
    }

    @objc private func toggleRecording() {
        if ScreenRecorder.shared.isRecording { ScreenRecorder.shared.stop(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { MainActor.assumeIsolated { ScreenRecorder.shared.toggle() } }
    }

    @objc private func captureTimer(_ sender: NSMenuItem) { CaptureOverlay.shared.start(.area, delay: sender.tag) }
    @objc private func pickColorFromMenu() { AppModel.shared.pickColor() }
    @objc private func openLastCapture() { ScreenshotService.shared.openLast() }
    @objc private func openCaptureHistory() { CaptureHistoryWindow.show() }
    @objc private func disableFaceUnlock() { FaceUnlockProvider.shared.disable(); statusItem?.menu = makeMenu() }
    @objc private func openSettings() { SettingsWindow.show() }

    enum MenuBarState { case idle, active, needsAction, presentation }

    /// The status the menu bar icon shows (design "Ikon menu bar", from icon 4c).
    static func menuBarState() -> MenuBarState {
        let m = AppModel.shared
        if m.presentationMode { return .presentation }
        if !m.center.urgentIDs.isEmpty || m.center.activities.values.contains(where: { $0.state == .needsAction }) { return .needsAction }
        return m.center.activities.isEmpty ? .idle : .active
    }

    /// Template icon from glyph 4c at 18 × 18 pt: the island (5.5 × 10) between two ears (3.5 × 6.5) fading from
    /// 62 % to 28 %. Ears turn solid while a Live Activity runs, a knocked-out dot means something needs you, and
    /// Presentation Mode draws the island as an outline with a slash. `dot`: Dylan drives the fans (D46).
    static func menuBarIcon(_ state: MenuBarState = .idle, dot: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let island = NSRect(x: 6.25, y: 4, width: 5.5, height: 10)
            NSColor.black.set()
            if state == .presentation {
                let outline = NSBezierPath(roundedRect: island.insetBy(dx: 0.625, dy: 0.625), xRadius: 2.125, yRadius: 2.125)
                outline.lineWidth = 1.25
                outline.stroke()
                let slash = NSBezierPath(roundedRect: NSRect(x: -6.8, y: -0.6, width: 13.6, height: 1.2), xRadius: 0.6, yRadius: 0.6)
                var t = AffineTransform(translationByX: 9, byY: 9)
                t.rotate(byDegrees: -38)
                slash.transform(using: t)
                slash.fill()
            } else {
                for (x, inner) in [(1.25, CGFloat(4.75)), (13.25, CGFloat(13.25))] {
                    let ear = NSBezierPath(roundedRect: NSRect(x: x, y: 5.75, width: 3.5, height: 6.5), xRadius: 1.75, yRadius: 1.75)
                    if state == .active {
                        ear.fill()
                    } else {
                        // Brighter next to the island, fainter outside.
                        let g = NSGradient(starting: NSColor.black.withAlphaComponent(0.62), ending: NSColor.black.withAlphaComponent(0.28))
                        g?.draw(in: ear, angle: inner > 9 ? 0 : 180)
                    }
                }
                let body = NSBezierPath(roundedRect: island, xRadius: 2.75, yRadius: 2.75)
                if state == .needsAction {
                    body.append(NSBezierPath(ovalIn: NSRect(x: 9 - 1.4, y: 9 - 1.4, width: 2.8, height: 2.8)).reversed)
                }
                body.fill()
            }
            if dot { NSBezierPath(ovalIn: NSRect(x: 14, y: 0.5, width: 4, height: 4)).fill() }
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
if let i = arguments.firstIndex(of: "--settings-snapshot"), i + 1 < arguments.count {
    if let l = arguments.firstIndex(of: "--lang"), l + 1 < arguments.count { L10n.forcedLanguage = arguments[l + 1] }
    let h = arguments.firstIndex(of: "--height").flatMap { $0 + 1 < arguments.count ? Double(arguments[$0 + 1]) : nil } ?? 660
    Snapshot.renderSettings(to: URL(fileURLWithPath: arguments[i + 1]), dark: arguments.contains("--dark"), height: h)
    exit(0)
}
// Records the real screen twice (whole screen, then an area) into /private/tmp, checks the MP4s, deletes them.
// No microphone; throwaway defaults, so the user's capture folder and settings are untouched.
if arguments.contains("--record-selftest") {
    let dir = "/private/tmp/dylan-rec-selftest-\(getpid())"
    let suite = "io.github.ramdanegie.dylan.selftest"
    AppModel.store = UserDefaults(suiteName: suite)!
    AppModel.store.set(dir, forKey: "shot.folder")
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    func spin(_ seconds: Double, until done: () -> Bool = { false }) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end && !done() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }
    guard CGPreflightScreenCaptureAccess(), let screen = NSScreen.main else {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        print("SKIP no Screen Recording permission"); exit(2)
    }
    var checks: [(String, Bool)] = []
    let area = CGRect(x: screen.frame.minX + 100, y: screen.frame.minY + 100, width: 401, height: 301)
    for (name, region, seconds) in [("screen", nil, 3.0), ("area", Optional(area), 2.0)] as [(String, CGRect?, Double)] {
        AppModel.shared.removeIfPresent("capture-saved", now: Date())
        let r = ScreenRecorder.shared
        r.start(region: region, screen: screen)
        spin(10) { r.isRecording }
        checks.append(("\(name): started", r.isRecording))
        spin(seconds)
        var finished = false
        r.stop { finished = true }
        spin(20) { finished }
        let path = AppModel.shared.center.activities["capture-saved"]?.url.map { String($0.dropFirst(6)) }
        checks.append(("\(name): file announced", path != nil))
        guard let path else { continue }
        var duration = 0.0, size = CGSize.zero
        Task {
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            duration = (try? await asset.load(.duration).seconds) ?? 0
            size = (try? await asset.loadTracks(withMediaType: .video).first?.load(.naturalSize)) ?? .zero
        }
        spin(10) { duration > 0 }
        let px = ScreenRecording.pixelSize(points: region?.size ?? screen.frame.size, scale: screen.backingScaleFactor)
        print(String(format: "  %@: %.1f s, %.0f×%.0f", name, duration, size.width, size.height))
        checks.append(("\(name): about \(Int(seconds)) s long", abs(duration - seconds) < 1.5))
        checks.append(("\(name): \(px.width)×\(px.height)", Int(size.width) == px.width && Int(size.height) == px.height))
    }
    for (name, ok) in checks { print(ok ? "PASS" : "FAIL", name) }
    try? FileManager.default.removeItem(atPath: dir)
    UserDefaults.standard.removePersistentDomain(forName: suite)
    exit(checks.allSatisfy(\.1) ? 0 : 1)
}
// Self-test of the Clean path on a throwaway home folder in /private/tmp (never the user's files or Trash).
if arguments.contains("--storage-selftest") {
    let fm = FileManager.default
    let base = "/private/tmp/dylan-storage-selftest-\(getpid())"
    func mk(_ rel: String, _ bytes: Int = 4096) {
        let path = base + "/" + rel
        try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        fm.createFile(atPath: path, contents: Data(count: bytes))
    }
    mk("Library/Caches/com.test.app/blob", 2_000_000)
    mk(".Trash/old.bin")
    mk("Downloads/keep.txt")
    try? fm.createSymbolicLink(atPath: base + "/Library/Caches/link", withDestinationPath: base + "/Downloads")
    let scanner = StorageScanner(home: base, running: [], capturesDir: base + "/none")
    let trashRow = scanner.scan(.trash).0
    mk(".Trash/new.bin")   // arrives after the scan: must survive "Empty Trash"
    let cache = StorageItem(category: .appCaches, title: "test", path: base + "/Library/Caches/com.test.app", size: 1)
    let link = StorageItem(category: .appCaches, title: "link", path: base + "/Library/Caches/link", size: 1)
    let r = StorageCleaner(home: base).clean([cache] + trashRow + [link])
    let checks: [(String, Bool)] = [
        ("cache deleted", !fm.fileExists(atPath: cache.path)),
        ("trash member removed", !fm.fileExists(atPath: base + "/.Trash/old.bin")),
        ("file trashed after the scan kept", fm.fileExists(atPath: base + "/.Trash/new.bin")),
        ("symlink refused", r.failed == 1 && fm.fileExists(atPath: base + "/Downloads/keep.txt")),
        ("trash folder kept", fm.fileExists(atPath: base + "/.Trash")),
    ]
    for (name, ok) in checks { print(ok ? "PASS" : "FAIL", name) }
    try? fm.removeItem(atPath: base)
    exit(checks.allSatisfy(\.1) ? 0 : 1)
}
// Read-only: prints what Optimize Storage would offer, deletes nothing.
if arguments.contains("--storage-scan") {
    let s = StorageScanner(home: NSHomeDirectory(), running: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
                           capturesDir: ScreenshotService.historyDir.path)
    for c in StorageCategory.allCases {
        let t0 = Date()
        let (items, denied) = s.scan(c)
        print(String(format: "  (%.1f s)", Date().timeIntervalSince(t0)))
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        print("\(c.rawValue) [\(c.impact) → \(c.action)] \(items.count) items, \(StorageProvider.bytes(total))\(denied ? " (no access)" : "")")
        for i in items.sorted(by: { $0.size > $1.size }).prefix(5) {
            print("   \(i.selectedByDefault ? "[x]" : "[ ]") \(StorageProvider.bytes(i.size))  \(i.title)  \((i.path as NSString).abbreviatingWithTildeInPath)\(i.note.map { "  (\($0))" } ?? "")")
        }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
