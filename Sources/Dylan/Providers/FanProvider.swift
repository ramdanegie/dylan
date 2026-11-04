import AppKit
import DylanCore
import IOKit
import ServiceManagement
import SMCKit
@preconcurrency import XPC

/// Temperatures and fans (FR-95 to FR-99, design D45–D49). Reading needs no privileges; fan speeds are written
/// by the root helper (Sources/DylanFanHelper) over XPC. Default preset is Auto, i.e. Dylan never touches the fans.
@Observable
final class FanProvider {
    static let shared = FanProvider()

    var fans: [SMC.Fan] = []
    var temps: [ThermalSensors.Group: Double] = [:]
    var sensorCount = 0
    var cpuHistory: [Double] = []
    private(set) var preset: FanPreset = .auto
    var helperStatus: SMAppService.Status = .notRegistered
    /// Shown in Settings when the helper refused a command.
    var lastError: String?

    var cpu: Double? { temps[.cpu] }
    var hasFans: Bool { !fans.isEmpty }
    /// A fan is manual although Dylan has not taken it (Macs Fan Control, TG Pro, …): hands off until the user picks a preset.
    var externallyControlled: Bool { preset == .auto && fans.contains(where: \.manual) }
    var throttling: Bool { ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue }
    let modelName: String = FanProvider.productName()

    @ObservationIgnored private let smc = SMC()
    @ObservationIgnored private let hid = HIDThermal()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var interval: TimeInterval = 0
    @ObservationIgnored private var conn: xpc_connection_t?
    @ObservationIgnored private var heat = HeatWatch()
    @ObservationIgnored private var smoother = Smoother(window: 10)
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var announceOnWake = false
    /// Held while Dylan drives the fans: App Nap must not stretch the 4 s heartbeat past the helper's 10 s watchdog.
    @ObservationIgnored private var noNap: NSObjectProtocol?
    @ObservationIgnored var tabOpen = false { didSet { refreshSchedule() } }

    // MARK: Settings (D48), stored like the other features in UserDefaults

    private var d: UserDefaults { AppModel.store }
    /// Indexed by SMC fan number; a fan whose read failed this tick leaves a gap, not a shift.
    private var slots: Int { (fans.map(\.index).max() ?? -1) + 1 }
    var modes: [FanMode] {
        get { (d.stringArray(forKey: "fan.modes") ?? []).compactMap(FanMode.init(rawValue:)).padded(to: slots, with: .curve) }
        set { d.set(newValue.map(\.rawValue), forKey: "fan.modes"); apply() }
    }
    var fixed: [Double] {
        get {
            let stored = (d.array(forKey: "fan.fixed") as? [Double] ?? []).padded(to: slots, with: 0)
            return (0..<slots).map { i in
                if stored[i] > 0 { return stored[i] }
                guard let f = fans.first(where: { $0.index == i }) else { return 0 }
                return f.min + (f.max - f.min) / 2
            }
        }
        set { d.set(newValue, forKey: "fan.fixed"); apply() }
    }
    var curve: FanCurve {
        get { (d.array(forKey: "fan.curve") as? [Double]).flatMap { $0.count == 4 ? FanCurve(percents: $0) : nil } ?? .standard }
        set { d.set(newValue.percents, forKey: "fan.curve"); apply() }
    }
    var sensor: ThermalSensors.Group {
        get { ThermalSensors.Group(rawValue: d.string(forKey: "fan.sensor") ?? "") ?? .cpu }
        set { d.set(newValue.rawValue, forKey: "fan.sensor"); apply() }
    }
    var smooth: Bool { d.object(forKey: "fan.smooth") as? Bool ?? true }
    var autoReturn: Bool { d.bool(forKey: "fan.autoReturn") }
    var warnOn: Bool { d.object(forKey: "fan.warnOn") as? Bool ?? true }
    var warnAt: Double { d.object(forKey: "fan.warnAt") as? Double ?? 95 }
    var menuTemp: Bool { d.bool(forKey: "fan.menuTemp") }
    /// Manual-mode status and "back to Auto" in the notch (D47); the heat warning has its own switch.
    var notchInfo: Bool { d.object(forKey: "fan.notchInfo") as? Bool ?? true }
    var fahrenheit: Bool { d.bool(forKey: "fan.fahrenheit") }

    func format(_ c: Double?) -> String {
        guard let c else { return "—" }
        return "\(Int((fahrenheit ? FanMath.fahrenheit(c) : c).rounded()))°"
    }

    // MARK: Lifecycle

    func start() {
        guard observers.isEmpty else { return }
        helperStatus = Self.service.status
        let ws = NSWorkspace.shared.notificationCenter
        observers = [
            // D47/FR-99: the fans always go back to Auto before sleep, and the notch says so after waking.
            ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { FanProvider.shared.sleeping() }
            },
            ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    let p = FanProvider.shared
                    if p.announceOnWake { p.announceOnWake = false; p.postAutoResult() }
                }
            },
        ]
        sample()
        refreshSchedule()
    }

    func stop() {
        if preset != .auto { setPreset(.auto, announce: false) }
        AppModel.shared.center.remove("fan-hot", now: Date())
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        timer?.invalidate(); timer = nil; interval = 0
    }

    /// 2 s with the tab open (design), 4 s while Dylan drives the fans (inside the helper's 10 s watchdog),
    /// 10 s for the heat warning and menu-bar temperature, otherwise nothing.
    func refreshSchedule() {
        let on = AppModel.shared.features.isEnabled(.thermal)
        let want: TimeInterval = !on ? 0 : tabOpen ? 2 : preset != .auto ? 4 : (warnOn || menuTemp) ? 10 : 0
        guard want != interval else { return }
        interval = want
        timer?.invalidate(); timer = nil
        guard want > 0 else { return }
        let t = Timer(timeInterval: want, repeats: true) { _ in MainActor.assumeIsolated { FanProvider.shared.sample() } }
        t.tolerance = want / 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func sample() {
        let readings = hid.read()
        sensorCount = readings.count
        temps = ThermalSensors.summarize(readings)
        fans = smc?.fans ?? []
        if let c = cpu { cpuHistory = Array((cpuHistory + [c]).suffix(60)) }
        let now = Date()
        if let c = cpu, warnOn {
            heat.threshold = warnAt
            if heat.overheated(c, at: now) { overheated(c) }
        }
        if preset != .auto, autoReturn, let c = cpu, heat.cooledDown(c, at: now) { setPreset(.auto) }
        drive()
        AppModel.shared.fanChanged()
    }

    // MARK: Presets

    func setPreset(_ p: FanPreset, announce: Bool = true) {
        guard p != preset || p == .auto else { return }
        if p != .auto, !AppModel.shared.features.isEnabled(.thermal) || !ensureHelper() { return }
        let was = preset
        preset = p
        smoother = Smoother(window: 10)
        heat.resetCool()
        if p == .auto {
            send("auto")
            AppModel.shared.center.remove("fan-manual", now: Date())
            if announce && was != .auto { postAutoResult() }
        }
        if p == .auto { noNap.map(ProcessInfo.processInfo.endActivity); noNap = nil }
        else if noNap == nil { noNap = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Fan control") }
        drive()
        refreshSchedule()
        AppModel.shared.fanChanged()
    }

    /// Per-fan mode from Settings: picking a mode switches to the custom curve preset (design D48).
    func setMode(_ m: FanMode, fan i: Int) {
        if m == .auto && preset != .curve { setPreset(.auto); return }
        var all = modes
        guard all.indices.contains(i) else { return }
        // Coming from another preset, the fans the UI showed as Auto stay Auto.
        if preset != .curve { all = all.map { _ in .auto } }
        all[i] = m
        modes = all
        if preset != .curve { setPreset(.curve) }
    }

    private func apply() { drive() }

    /// Sends the target for every fan. Also the heartbeat for the helper's watchdog.
    private func drive() {
        guard preset != .auto, !fans.isEmpty else { return }
        let now = Date()
        // No reading → temperature-driven fans go back to macOS rather than run blind.
        let raw = temps[preset == .curve ? sensor : .cpu] ?? cpu
        let t = raw.map { smooth ? smoother.add($0, at: now) : $0 }
        let modes = modes, fixed = fixed
        for f in fans {
            let target: Double?
            switch preset {
            case .auto: target = nil
            case .curve:
                switch modes[f.index] {
                case .auto: target = nil
                case .fixed: target = fixed[f.index]
                case .curve: target = t.map { FanMath.rpm(curve.percent(at: $0) / 100, min: f.min, max: f.max) }
                }
            default: target = t.flatMap { preset.fraction(cpu: $0) }.map { FanMath.rpm($0, min: f.min, max: f.max) }
            }
            if let target { send("set", fan: f.index, rpm: target) } else { send("auto", fan: f.index) }
        }
        postManual()
    }

    private func sleeping() {
        guard preset != .auto else { return }
        setPreset(.auto, announce: false)
        announceOnWake = true   // D47: the result shows after waking
    }

    // MARK: Helper (D49)

    static let service = SMAppService.daemon(plistName: FanHelperAPI.plist)

    /// The helper only trusts an app signed by its own team; ad-hoc builds can monitor but not control.
    static let signedByTeam: Bool = {
        var code: SecCode?, s: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code, SecCodeCopyStaticCode(code, [], &s) == errSecSuccess, let s,
              SecCodeCopySigningInformation(s, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return false }
        return ((info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String).map { !$0.isEmpty } ?? false
    }()

    var canControl: Bool { hasFans && Self.signedByTeam }

    /// true when the helper is running; otherwise shows the permission sheet (D49) and returns false.
    private func ensureHelper() -> Bool {
        helperStatus = Self.service.status
        guard helperStatus == .enabled, canControl else {
            HelperSheetWindow.show()
            return false
        }
        return true
    }

    func installHelper() {
        lastError = nil
        do { try Self.service.register() } catch { lastError = error.localizedDescription }
        helperStatus = Self.service.status
        if helperStatus == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    func removeHelper() {
        setPreset(.auto, announce: false)
        conn.map(xpc_connection_cancel); conn = nil
        // @Sendable: SMAppService calls back off the main thread (a main-actor closure would trap).
        Self.service.unregister { @Sendable _ in Task { @MainActor in FanProvider.shared.helperStatus = FanProvider.service.status } }
    }

    private func send(_ op: String, fan: Int = -1, rpm: Double = 0) {
        guard Self.signedByTeam, helperStatus == .enabled else { return }
        if conn == nil {
            let c = xpc_connection_create_mach_service(FanHelperAPI.label, .main, UInt64(XPC_CONNECTION_MACH_SERVICE_PRIVILEGED))
            xpc_connection_set_event_handler(c) { e in
                // Interrupted (helper restarted, it has restored Auto) or invalid: reconnect on the next send.
                if xpc_get_type(e) == XPC_TYPE_ERROR { MainActor.assumeIsolated { FanProvider.shared.conn = nil } }
            }
            xpc_connection_activate(c)
            conn = c
        }
        let m = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(m, "op", op)
        xpc_dictionary_set_int64(m, "fan", Int64(fan))
        xpc_dictionary_set_double(m, "rpm", rpm)
        xpc_connection_send_message_with_reply(conn!, m, .main) { r in
            let ok = xpc_get_type(r) == XPC_TYPE_DICTIONARY && xpc_dictionary_get_bool(r, "ok")
            MainActor.assumeIsolated { FanProvider.shared.lastError = ok ? nil : L("fan.helperFailed") }
        }
    }

    // MARK: Notch (D47)

    func postManual() {
        guard notchInfo, preset != .auto else { AppModel.shared.center.remove("fan-manual", now: Date()); return }
        // Stays while manual (upsert, not post: a posted activity expires after its hold).
        let rpm = fans.first.map { Self.rpm($0.rpm) } ?? ""
        AppModel.shared.center.upsert(Activity(
            id: "fan-manual", kind: .thermal, priority: .p3, state: .ambient, symbol: "fan",
            label: L("fan.preset.\(preset.rawValue)"), value: rpm, detail: L("fan.manualDetail", L("fan.preset.\(preset.rawValue)")),
            startedAt: AppModel.shared.center.activities["fan-manual"]?.startedAt ?? Date()))
    }

    private func postAutoResult() {
        guard notchInfo else { return }
        let now = Date()
        AppModel.shared.center.post(Activity(
            id: "fan-auto", kind: .thermal, priority: .p2, state: .success, symbol: "checkmark",
            label: L("fan.preset.auto"), value: "CPU " + format(cpu), detail: L("fan.backToAuto"), startedAt: now, endedAt: now), now: now)
        AppModel.shared.scheduleTick()
    }

    private func overheated(_ c: Double) {
        let atMax = preset == .max
        Task.detached {
            let procs = Stats.parsePS(Shell.run("/bin/ps", ["-Aceo", "pid=,pcpu=,rss=,comm=", "-r"]) ?? "")
            await MainActor.run { FanProvider.shared.postOverheat(c, top: procs.first { $0.pid != getpid() }, atMax: atMax) }
        }
    }

    private func postOverheat(_ c: Double, top: Stats.Process?, atMax: Bool) {
        let now = Date()
        let who = top.map { L("fan.hotBy", $0.name, Int($0.cpu)) } ?? L("fan.hot")
        AppModel.shared.center.post(Activity(
            id: "fan-hot", kind: .thermal, priority: .p1, state: .needsAction, symbol: "thermometer.high",
            label: format(c), value: fans.first.map { Self.rpm($0.rpm) } ?? "", detail: who, genericDetail: L("fan.hot"),
            url: atMax || !canControl ? nil : "fan:max", startedAt: now), now: now)
        AppModel.shared.scheduleTick()
    }

    func perform(_ action: String) {
        switch action {
        case "max": setPreset(.max)
        case "processes": NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        default: break
        }
        AppModel.shared.center.remove("fan-hot", now: Date())
    }

    static func rpm(_ v: Double) -> String { "\(Int(v).formatted(.number.locale(L10n.locale))) rpm" }

    private static func productName() -> String {
        let chip = Shell.run("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"])
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        defer { IOObjectRelease(entry) }
        let name = (IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data)
            .flatMap { String(data: $0, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) } ?? "Mac"
        return [name, chip?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "Apple ", with: "")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// IOHID temperature sensors (private IOKit API, looked up at runtime like SkyLight elsewhere). No privileges needed.
final class HIDThermal {
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyProp = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloat = @convention(c) (AnyObject, Int32) -> Double

    private let client: AnyObject?
    private let copyServices: CopyServices?, copyProp: CopyProp?, copyEvent: CopyEvent?, getFloat: GetFloat?

    init() {
        let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        func sym<T>(_ n: String) -> T? { dlsym(h, n).map { unsafeBitCast($0, to: T.self) } }
        copyServices = sym("IOHIDEventSystemClientCopyServices")
        copyProp = sym("IOHIDServiceClientCopyProperty")
        copyEvent = sym("IOHIDServiceClientCopyEvent")
        getFloat = sym("IOHIDEventGetFloatValue")
        let create: Create? = sym("IOHIDEventSystemClientCreate"), setMatching: SetMatching? = sym("IOHIDEventSystemClientSetMatching")
        client = create?(kCFAllocatorDefault)?.takeRetainedValue()
        // Vendor page 0xff00, usage 5: temperature sensors.
        if let client { _ = setMatching?(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary) }
    }

    func read() -> [(String, Double)] {
        guard let client, let copyServices, let copyProp, let copyEvent, let getFloat,
              let services = copyServices(client)?.takeRetainedValue() as? [AnyObject] else { return [] }
        let temperature: Int64 = 15
        return services.compactMap { s in
            guard let name = copyProp(s, "Product" as CFString)?.takeRetainedValue() as? String,
                  let e = copyEvent(s, temperature, 0, 0)?.takeRetainedValue() else { return nil }
            return (name, getFloat(e, Int32(temperature << 16)))
        }
    }
}

private extension Array {
    func padded(to n: Int, with v: Element) -> [Element] { count >= n ? self : self + Array(repeating: v, count: n - count) }
}

extension FanProvider {
    /// "Left fan" / "Right fan" on two-fan Macs (design D45), otherwise "Fan" or "Fan 2".
    static func fanName(_ i: Int, of n: Int) -> String {
        n == 2 ? L(i == 0 ? "fan.left" : "fan.right") : n == 1 ? L("fan.single") : L("fan.numbered", i + 1)
    }
}
