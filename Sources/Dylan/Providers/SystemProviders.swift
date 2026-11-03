import AppKit
import CoreAudio
import CoreMediaIO
import DylanCore
import EventKit
import IOBluetooth
import IOKit.ps

// MARK: Calendar (PRD §F6)

final class CalendarProvider {
    static let shared = CalendarProvider()
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var dayObserver: NSObjectProtocol?
    private(set) var authorized = false

    var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }

    func start(requestAccess: Bool) {
        if status == .fullAccess { begin(); return }
        guard requestAccess, status == .notDetermined else { return }
        store.requestFullAccessToEvents { @Sendable granted, _ in
            Task { @MainActor in if granted { CalendarProvider.shared.begin() } }
        }
    }

    private func begin() {
        authorized = true
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
                MainActor.assumeIsolated { CalendarProvider.shared.reload() }
            }
            // The window is "today + 24 h": reload at midnight as well.
            dayObserver = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { CalendarProvider.shared.reload() }
            }
        }
        reload()
    }

    func stop() {
        for o in [observer, dayObserver].compactMap({ $0 }) { NotificationCenter.default.removeObserver(o) }
        observer = nil
        dayObserver = nil
        authorized = false
        AppModel.shared.meetings = []
        AppModel.shared.refreshMeeting()
    }

    func reload() {
        guard authorized, AppModel.shared.features.isEnabled(.meeting) else { return }
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let end = now.addingTimeInterval(24 * 3600)
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
        AppModel.shared.meetings = events.filter { $0.status != .canceled }.map { e in
            MeetingSchedule.Event(id: e.calendarItemIdentifier + "\(e.startDate.timeIntervalSince1970)",
                                  title: e.title ?? "", start: e.startDate, end: e.endDate,
                                  link: MeetingLink.find(in: [e.url?.absoluteString, e.location, e.notes]),
                                  isAllDay: e.isAllDay)
        }
        AppModel.shared.refreshMeeting()
        AppModel.shared.scheduleTick()
    }
}

// MARK: Battery (FR-70)

final class BatteryProvider {
    static let shared = BatteryProvider()
    private var source: CFRunLoopSource?
    private var lowPowerObserver: NSObjectProtocol?

    func start() {
        guard source == nil else { return }
        let cb: IOPowerSourceCallbackType = { _ in MainActor.assumeIsolated { BatteryProvider.shared.read() } }
        if let s = IOPSNotificationCreateRunLoopSource(cb, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .defaultMode)
            source = s
        }
        lowPowerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BatteryProvider.shared.read() }
        }
        read()
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
        if let lowPowerObserver { NotificationCenter.default.removeObserver(lowPowerObserver) }
    }

    func read() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let ttf = d[kIOPSTimeToFullChargeKey] as? Int ?? -1
            AppModel.shared.batteryChanged(BatterySnapshot(
                percent: max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur,
                isCharging: d[kIOPSIsChargingKey] as? Bool ?? false,
                onAC: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                minutesToFull: ttf > 0 ? ttf : nil,
                lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled))
            return
        }
    }
}

// MARK: Bluetooth (FR-44, spike T0.6)

final class BluetoothProvider: NSObject {
    static let shared = BluetoothProvider()
    private var connectNote: IOBluetoothUserNotification?
    private var seen: Set<String> = []

    func start() {
        guard connectNote == nil else { return }
        // Already-connected devices fire once on registration; ignore that first burst.
        let started = Date()
        startedAt = started
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    private var startedAt = Date.distantPast

    func stop() {
        connectNote?.unregister()
        connectNote = nil
    }

    @objc private func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
        guard Date().timeIntervalSince(startedAt) > 2 else { return }
        post(device, connected: true)
    }

    @objc private func disconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        note.unregister()
        post(device, connected: false)
    }

    private func post(_ device: IOBluetoothDevice, connected: Bool) {
        let model = AppModel.shared
        guard model.features.isEnabled(.bluetooth) else { return }
        let name = device.name ?? L("bluetooth.device")
        let now = Date()
        model.center.post(Activity(
            id: "bluetooth-\(device.addressString ?? name)", kind: .bluetooth, priority: .p1,
            state: connected ? .success : .info, symbol: Self.symbol(for: device),
            label: TextRules.truncateTail(name, max: 12), value: connected ? L("bluetooth.connectedShort") : L("bluetooth.disconnectedShort"),
            detail: L(connected ? "bluetooth.connected" : "bluetooth.disconnected", name), startedAt: now), now: now)
        model.scheduleTick()
        if connected, let addr = device.addressString { readBattery(id: "bluetooth-\(addr)", address: addr, name: name) }
    }

    /// Battery levels arrive a few seconds after the connection (FR-44, design M8). One system_profiler run per connect.
    private func readBattery(id: String, address: String, name: String) {
        Task.detached {
            try? await Task.sleep(for: .seconds(1.5))
            let out = Shell.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"], timeout: 15)
            guard let levels = out.flatMap({ BluetoothBattery.parse(Data($0.utf8))[BluetoothBattery.normalize(address)] }) else { return }
            await MainActor.run {
                let m = AppModel.shared
                guard var a = m.center.activities[id], a.state == .success else { return }   // gone, or disconnected meanwhile
                a.value = BluetoothBattery.lowest(levels).map { "\($0)%" } ?? a.value
                a.detail = L("bluetooth.connected", name) + " · " + BluetoothBattery.summary(levels)
                m.center.upsert(a)
            }
        }
    }

    static func symbol(for d: IOBluetoothDevice) -> String {
        let n = (d.name ?? "").lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        switch d.deviceClassMajor {
        case UInt32(kBluetoothDeviceClassMajorAudio): return "headphones"
        case UInt32(kBluetoothDeviceClassMajorPeripheral):
            return d.deviceClassMinor & 0x10 != 0 ? "keyboard" : (d.deviceClassMinor & 0x20 != 0 ? "computermouse" : "gamecontroller")
        default: return "dot.radiowaves.left.and.right"
        }
    }
}

// MARK: Camera & microphone in use (FR-71)

final class PrivacyProvider {
    static let shared = PrivacyProvider()
    private var micDevice = AudioObjectID(kAudioObjectUnknown)
    private var micListener: AudioObjectPropertyListenerBlock?
    private var cameras: [CMIOObjectID: CMIOObjectPropertyListenerBlock] = [:]
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        var defaultInput = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultInput, .main) { _, _ in
            MainActor.assumeIsolated { PrivacyProvider.shared.watchMic() }
        }
        watchMic()
        watchCameras()
        // Continuity Camera or a USB webcam plugged in later must light the dot too.
        var devices = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &devices, .main) { _, _ in
            MainActor.assumeIsolated { PrivacyProvider.shared.watchCameras() }
        }
    }

    private static func runningAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                   mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func cameraRunningAddress() -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
    }

    private func watchMic() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dev = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr,
              dev != micDevice else { update(); return }
        // Remove the listener on the previous default input before adding one to the new device.
        var running = Self.runningAddress()
        if let old = micListener, micDevice != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(micDevice, &running, .main, old)
        }
        micDevice = dev
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { PrivacyProvider.shared.update() }
        }
        AudioObjectAddPropertyListenerBlock(dev, &running, .main, block)
        micListener = block
        update()
    }

    fileprivate func watchCameras() {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == 0 else { return }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == 0 else { return }
        // Watch new devices once; forget unplugged ones.
        for gone in cameras.keys where !ids.contains(gone) {
            var r = Self.cameraRunningAddress()
            if let b = cameras[gone] { CMIOObjectRemovePropertyListenerBlock(gone, &r, .main, b) }
            cameras[gone] = nil
        }
        for id in ids where cameras[id] == nil {
            var r = Self.cameraRunningAddress()
            let block: CMIOObjectPropertyListenerBlock = { _, _ in
                MainActor.assumeIsolated { PrivacyProvider.shared.update() }
            }
            CMIOObjectAddPropertyListenerBlock(id, &r, .main, block)
            cameras[id] = block
        }
        update()
    }

    func update() {
        let model = AppModel.shared
        guard model.features.isEnabled(.privacy) else { model.cameraOn = false; model.micOn = false; return }
        model.micOn = isRunning(micDevice)
        model.cameraOn = cameras.keys.contains { cameraRunning($0) }
        let user = model.micOn ? micUser() : nil
        model.micApp = user?.name
        model.micAppProcess = user.map { ($0.pid, $0.bundleID) }
        model.refreshDiscordSimple()
        MeetingCallProvider.shared.micChanged()
    }

    private func isRunning(_ dev: AudioObjectID) -> Bool {
        guard dev != kAudioObjectUnknown else { return false }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr && v != 0
    }

    private func cameraRunning(_ id: CMIOObjectID) -> Bool {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
        var v: UInt32 = 0
        var used: UInt32 = 0
        return CMIOObjectGetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &v) == 0 && v != 0
    }

    /// Which app records audio, via Core Audio process objects (macOS 14.2+). Best effort.
    private func micUser() -> (name: String, pid: pid_t, bundleID: String?)? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return nil }
        for p in ids {
            var inAddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput,
                                                    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var on: UInt32 = 0
            var s = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(p, &inAddr, 0, nil, &s, &on) == noErr, on != 0 else { continue }
            var pidAddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                                     mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = 0
            var ps = UInt32(MemoryLayout<pid_t>.size)
            if AudioObjectGetPropertyData(p, &pidAddr, 0, nil, &ps, &pid) == noErr,
               let app = Self.owningApp(pid: pid, processObject: p), let name = app.localizedName {
                return (name, app.processIdentifier, app.bundleIdentifier)
            }
        }
        return nil
    }
}

extension PrivacyProvider {
    /// Browsers record from a helper (com.google.Chrome.helper, Safari's WebKit GPU process): map it to the app.
    static func owningApp(pid: pid_t, processObject p: AudioObjectID) -> NSRunningApplication? {
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular { return app }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(p, &addr, 0, nil, &size, &cf) == noErr, let raw = cf?.takeRetainedValue() as String? else { return nil }
        let id = raw.hasPrefix("com.apple.WebKit") ? "com.apple.Safari"
            : (raw.range(of: #"\.helper.*$"#, options: [.regularExpression, .caseInsensitive]).map { String(raw[..<$0.lowerBound]) } ?? raw)
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).first
            ?? NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier?.caseInsensitiveCompare(id) == .orderedSame }
    }
}

// MARK: Focus the terminal/editor of an agent session (PRD §F3, §2.6 table)

enum TerminalFocus {
    static func focus(_ s: AgentSessions.Session?) {
        guard let s else { return }
        let ws = NSWorkspace.shared
        let root = s.cwd.map { URL(fileURLWithPath: $0) }
        let bundle = s.appBundleID ?? bundleFromTerm(s.termProgram)
        guard let bundle, let appURL = ws.urlForApplication(withBundleIdentifier: bundle) else { return }
        // VS Code / Zed: opening the folder brings the right project window forward.
        if ["com.microsoft.VSCode", "dev.zed.Zed", "com.todesktop.230313mzl4w4u92"].contains(bundle), let root {
            ws.open([root], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            // openApplication activates reliably from an accessory app (activate() can be ignored
            // under cooperative activation on macOS 14+).
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            ws.openApplication(at: appURL, configuration: config)
        }
    }

    static func bundleFromTerm(_ term: String?) -> String? {
        switch term {
        case "vscode": return "com.microsoft.VSCode"
        case "zed": return "dev.zed.Zed"
        case "Apple_Terminal": return "com.apple.Terminal"
        case "iTerm.app": return "com.googlecode.iterm2"
        case "ghostty": return "com.mitchellh.ghostty"
        default: return nil
        }
    }
}
