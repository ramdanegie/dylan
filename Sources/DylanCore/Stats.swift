import Foundation

/// System stats math (FR-26, PRD §F13). Sampling happens in the app; deltas and parsing live here.
public enum Stats {
    /// CPU ticks per core: (user, system, idle, nice).
    public struct Ticks: Equatable, Sendable {
        public var user, system, idle, nice: UInt64
        public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
            self.user = user; self.system = system; self.idle = idle; self.nice = nice
        }
        var busy: UInt64 { user &+ system &+ nice }
        var total: UInt64 { busy &+ idle }
    }

    /// Overall CPU use between two samples, 0…1.
    public static func cpuUsage(previous: [Ticks], current: [Ticks]) -> Double {
        guard previous.count == current.count, !current.isEmpty else { return 0 }
        var busy: UInt64 = 0, total: UInt64 = 0
        for (p, c) in zip(previous, current) {
            guard c.total >= p.total, c.busy >= p.busy else { continue }   // counter reset after sleep
            busy &+= c.busy - p.busy
            total &+= c.total - p.total
        }
        return total == 0 ? 0 : min(1, Double(busy) / Double(total))
    }

    /// Bytes per second from two interface counters taken `interval` seconds apart.
    public static func rate(previous: UInt64, current: UInt64, interval: TimeInterval) -> Double {
        guard interval > 0, current >= previous else { return 0 }
        return Double(current - previous) / interval
    }

    /// `1,2 MB/s`, `180 KB/s` (decimal units, like Activity Monitor).
    public static func formatRate(_ bytesPerSecond: Double, locale: Locale = Locale(identifier: "id_ID")) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .decimal
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.allowsNonnumericFormatting = false   // "0 KB", not "Zero KB"
        return f.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    public struct Process: Equatable, Sendable {
        public var pid: Int32
        public var cpu: Double      // percent; can exceed 100 on multi-core
        public var rssKB: Int
        public var name: String
    }

    /// Parses `ps -Aceo pid=,pcpu=,rss=,comm=` output (sorted by the caller or not).
    public static func parsePS(_ output: String) -> [Process] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]),
                  let cpu = Double(parts[1].replacingOccurrences(of: ",", with: ".")), let rss = Int(parts[2]) else { return nil }
            return Process(pid: pid, cpu: cpu, rssKB: rss, name: String(parts[3]))
        }
    }
}

/// "node memakai 180% CPU · 2 menit": a process above the limit for long enough (PRD §F13, [Dev]).
public struct CPUAlertTracker: Sendable {
    public var threshold: Double = 150
    public var duration: TimeInterval = 60
    private var since: [Int32: Date] = [:]
    private var alerted: Set<Int32> = []
    public init() {}

    /// Feed one sample of all processes; returns processes that just crossed the alert rule.
    public mutating func feed(_ procs: [Stats.Process], now: Date) -> [(Stats.Process, TimeInterval)] {
        var out: [(Stats.Process, TimeInterval)] = []
        let hot = Dictionary(procs.filter { $0.cpu >= threshold }.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        for pid in Array(since.keys) where hot[pid] == nil { since[pid] = nil; alerted.remove(pid) }
        for (pid, p) in hot {
            let start = since[pid] ?? now
            since[pid] = start
            let d = now.timeIntervalSince(start)
            if d >= duration, !alerted.contains(pid) { alerted.insert(pid); out.append((p, d)) }
        }
        return out.sorted { $0.0.cpu > $1.0.cpu }
    }

    public func hotSince(_ pid: Int32) -> Date? { since[pid] }
}

/// Listening TCP ports from `lsof -nP -iTCP -sTCP:LISTEN -F pcn` (FR-25, PRD §F10).
public enum PortScan {
    public struct Listener: Equatable, Sendable, Hashable {
        public var port: Int
        public var pid: Int32
        public var command: String
        public init(port: Int, pid: Int32, command: String) { self.port = port; self.pid = pid; self.command = command }
    }

    /// System and app ports that are not dev servers (ControlCenter AirPlay 5000/7000, Spotify, Docker internals, …).
    public static let ignoredCommands: Set<String> = ["ControlCe", "ControlCenter", "rapportd", "Spotify", "com.docke", "com.docker",
                                                      "Dylan", "sharingd", "identitys", "Raycast", "Figma", "Dropbox", "Code Helper"]

    public static func parse(_ output: String) -> [Listener] {
        var out: Set<Listener> = []
        var pid: Int32?
        var command = ""
        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int32(value); command = ""
            case "c": command = value
            case "n":
                guard let pid, let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]) else { continue }
                out.insert(Listener(port: port, pid: pid, command: command))
            default: continue
            }
        }
        return out.sorted { $0.port < $1.port }
    }

    /// Dev-server candidates: not ignored, not in the ephemeral range.
    public static func devServers(_ all: [Listener], extraIgnored: Set<String> = []) -> [Listener] {
        all.filter { l in
            l.port < 49152 && !ignoredCommands.union(extraIgnored).contains { l.command.hasPrefix($0) }
        }
    }

    /// Ports that appeared since the last scan (the first scan never announces anything).
    public static func newPorts(previous: [Listener]?, current: [Listener]) -> [Listener] {
        guard let previous else { return [] }
        let old = Set(previous.map(\.port))
        return current.filter { !old.contains($0.port) }
    }
}
