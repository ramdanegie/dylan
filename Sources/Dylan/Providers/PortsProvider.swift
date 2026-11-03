import AppKit
import Darwin
import DylanCore

/// Dev servers on listening TCP ports (FR-25, PRD §F10). [Dev] only; `lsof` every 10 s while enabled.
@Observable
final class PortsProvider {
    static let shared = PortsProvider()

    struct Server: Identifiable, Equatable {
        var listener: PortScan.Listener
        var project: String?
        var id: Int { listener.port }
    }

    var servers: [Server] = []
    @ObservationIgnored private var previous: [PortScan.Listener]?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var projects: [Int32: String] = [:]

    func start() {
        guard timer == nil else { return }
        scan()
        let t = Timer(timeInterval: 10, repeats: true) { _ in MainActor.assumeIsolated { PortsProvider.shared.scan() } }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate(); timer = nil
        previous = nil
        servers = []
    }

    func scan() {
        Task.detached {
            let out = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]) ?? ""
            let found = PortScan.devServers(PortScan.parse(out))
            // Collapse IPv4/IPv6 listeners of one port.
            var seen = Set<Int>()
            let unique = found.filter { seen.insert($0.port).inserted }
            await MainActor.run { PortsProvider.shared.update(unique) }
        }
    }

    private func update(_ listeners: [PortScan.Listener]) {
        let fresh = PortScan.newPorts(previous: previous, current: listeners)
        previous = listeners
        projects = projects.filter { pid, _ in listeners.contains { $0.pid == pid } }
        servers = listeners.map { l in
            if projects[l.pid] == nil, let cwd = Self.cwd(of: l.pid) { projects[l.pid] = ProjectName.resolve(cwd: cwd) }
            return Server(listener: l, project: projects[l.pid])
        }
        let m = AppModel.shared
        for l in fresh {
            let now = Date()
            let project = projects[l.pid] ?? l.command
            m.center.post(Activity(id: "port-\(l.port)", kind: .port, priority: .p1, state: .success, symbol: "network",
                                   label: ":\(l.port)", value: TextRules.truncateTail(project, max: 12),
                                   detail: L("ports.ready", String(l.port), project), genericDetail: L("ports.readyGeneric"),
                                   url: "http://localhost:\(l.port)", startedAt: now), now: now)
            m.scheduleTick()
        }
    }

    /// Working directory of a process (libproc), used to name the project.
    nonisolated static func cwd(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { p in
                let s = String(decoding: UnsafeRawBufferPointer(start: p, count: strnlen(p, Int(MAXPATHLEN))), as: UTF8.self)
                return s.isEmpty || s == "/" ? nil : s
            }
        }
    }

    func open(_ s: Server) { NSWorkspace.shared.open(URL(string: "http://localhost:\(s.listener.port)")!) }

    func copy(_ s: Server) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("http://localhost:\(s.listener.port)", forType: .string)
    }

    /// SIGTERM, then SIGKILL after 3 s if it is still alive (confirmed in the UI).
    func kill(_ s: Server) {
        StatsProvider.shared.stop(s.listener.pid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { PortsProvider.shared.scan() }
    }
}
