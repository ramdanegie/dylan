import AppKit
import Darwin
import DylanCore
import IOKit

/// Samples CPU, GPU, memory, network and disk (FR-26). 1 s while the Stats tab is open;
/// otherwise every 10 s, and only for the [Dev] CPU alert. Nothing runs when both are off.
@Observable
final class StatsProvider {
    static let shared = StatsProvider()

    var cpu: Double = 0
    var cpuHistory: [Double] = []
    var gpu: Double?
    var memUsed: UInt64 = 0
    let memTotal = ProcessInfo.processInfo.physicalMemory
    var netDown: Double = 0
    var netUp: Double = 0
    var diskUsed: Int64 = 0
    var diskTotal: Int64 = 0
    var topProcesses: [Stats.Process] = []

    @ObservationIgnored private var lastTicks: [Stats.Ticks] = []
    @ObservationIgnored private var lastNet: (down: UInt64, up: UInt64, at: Date)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var interval: TimeInterval = 0
    @ObservationIgnored private var alerts = CPUAlertTracker()

    /// Called when the Stats tab opens/closes or the profile changes.
    func refreshSchedule() {
        let m = AppModel.shared
        let tabOpen = m.notchState == .expanded && m.selectedTab == .stats
        let want: TimeInterval = tabOpen ? 1 : (m.isDeveloper && m.features.isEnabled(.stats) ? 10 : 0)
        guard want != interval else { return }
        interval = want
        timer?.invalidate(); timer = nil
        guard want > 0 else { return }
        sample(full: tabOpen)
        let t = Timer(timeInterval: want, repeats: true) { _ in
            MainActor.assumeIsolated { StatsProvider.shared.sample(full: StatsProvider.shared.interval == 1) }
        }
        t.tolerance = want / 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func sample(full: Bool) {
        if full {
            let ticks = Self.cpuTicks()
            if !lastTicks.isEmpty { cpu = Stats.cpuUsage(previous: lastTicks, current: ticks) }
            lastTicks = ticks
            cpuHistory = Array((cpuHistory + [cpu]).suffix(60))
            gpu = Self.gpuUtilization()
            memUsed = Self.memoryUsed()
            let now = Date(), n = Self.networkBytes()
            if let l = lastNet {
                let dt = now.timeIntervalSince(l.at)
                netDown = Stats.rate(previous: l.down, current: n.down, interval: dt)
                netUp = Stats.rate(previous: l.up, current: n.up, interval: dt)
            }
            lastNet = (n.down, n.up, now)
            if let a = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
               let total = (a[.systemSize] as? NSNumber)?.int64Value, let free = (a[.systemFreeSize] as? NSNumber)?.int64Value {
                diskTotal = total; diskUsed = total - free
            }
        }
        // `ps` runs off the main thread; the alert check needs it in both modes.
        Task.detached {
            let out = Shell.run("/bin/ps", ["-Aceo", "pid=,pcpu=,rss=,comm=", "-r"]) ?? ""
            let procs = Stats.parsePS(out)
            await MainActor.run { StatsProvider.shared.processesSampled(procs) }
        }
    }

    private func processesSampled(_ procs: [Stats.Process]) {
        topProcesses = Array(procs.prefix(4))
        let m = AppModel.shared
        guard m.isDeveloper, m.features.isEnabled(.stats) else { return }
        for (p, d) in alerts.feed(procs, now: Date()) where p.pid != getpid() {
            let now = Date()
            m.center.post(Activity(id: "cpu-\(p.pid)", kind: .notify, priority: .p1, state: .needsAction, symbol: "cpu",
                                   label: "CPU", value: "\(Int(p.cpu))%",
                                   detail: L("stats.alert", p.name, Int(p.cpu), DurationFormat.long(d, language: L10n.language)),
                                   genericDetail: L("stats.alertGeneric"), url: "pid:\(p.pid)", startedAt: now), now: now)
            m.scheduleTick()
        }
    }

    func isHot(_ pid: Int32) -> Bool { alerts.hotSince(pid) != nil }

    /// SIGTERM, then SIGKILL after 3 s if it is still alive (user confirmed in the UI).
    func stop(_ pid: Int32) {
        guard pid > 1, pid != getpid() else { return }
        kill(pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
    }

    // MARK: Samplers

    private static func cpuTicks() -> [Stats.Ticks] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)) }
        return (0..<Int(count)).map { i in
            let b = Int(CPU_STATE_MAX) * i
            return Stats.Ticks(user: UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_USER)])),
                               system: UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_SYSTEM)])),
                               idle: UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_IDLE)])),
                               nice: UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_NICE)])))
        }
    }

    private static func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return 0 }
        let page = UInt64(sysconf(_SC_PAGESIZE))
        // Same idea as Activity Monitor's "Memory Used": app (active + wired) + compressed.
        return (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    private static func networkBytes() -> (down: UInt64, up: UInt64) {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return (0, 0) }
        defer { freeifaddrs(ifap) }
        var down: UInt64 = 0, up: UInt64 = 0
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data,
                  (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            down &+= UInt64(d.ifi_ibytes); up &+= UInt64(d.ifi_obytes)
        }
        return (down, up)
    }

    /// Apple Silicon publishes GPU load in IOAccelerator's PerformanceStatistics. Best effort.
    private static func gpuUtilization() -> Double? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var best: Double?
        while case let entry = IOIteratorNext(it), entry != 0 {
            defer { IOObjectRelease(entry) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let perf = dict["PerformanceStatistics"] as? [String: Any],
                  let util = perf["Device Utilization %"] as? NSNumber else { continue }
            best = max(best ?? 0, util.doubleValue / 100)
        }
        return best
    }
}
