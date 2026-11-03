import Foundation
import Testing
@testable import DylanCore

@Suite struct StatsTests {
    @Test func cpuUsageFromTicks() {
        let a = [Stats.Ticks(user: 100, system: 50, idle: 850, nice: 0), Stats.Ticks(user: 0, system: 0, idle: 1000, nice: 0)]
        let b = [Stats.Ticks(user: 150, system: 75, idle: 875, nice: 0), Stats.Ticks(user: 50, system: 0, idle: 1050, nice: 0)]
        // core 1: 75 busy / 100; core 2: 50 / 100 → 125 / 200
        #expect(Stats.cpuUsage(previous: a, current: b) == 0.625)
        #expect(Stats.cpuUsage(previous: b, current: a) == 0)        // counters went backwards (sleep): ignored
        #expect(Stats.cpuUsage(previous: [], current: b) == 0)
    }

    @Test func rates() {
        #expect(Stats.rate(previous: 1000, current: 3000, interval: 2) == 1000)
        #expect(Stats.rate(previous: 3000, current: 1000, interval: 2) == 0)
        #expect(Stats.formatRate(1_200_000, locale: Locale(identifier: "en_US")).hasSuffix("/s"))
    }

    @Test func parsesPS() {
        let out = """
          412 182.3 1468000 node
          88  34,0   820000 Code Helper (Renderer)
        garbage line
        """
        let p = Stats.parsePS(out)
        #expect(p.count == 2)
        #expect(p[0] == Stats.Process(pid: 412, cpu: 182.3, rssKB: 1_468_000, name: "node"))
        #expect(p[1].name == "Code Helper (Renderer)" && p[1].cpu == 34)
    }

    @Test func alertAfterSixtySecondsOnce() {
        var t = CPUAlertTracker()
        let t0 = Date(timeIntervalSince1970: 0)
        let node = Stats.Process(pid: 412, cpu: 180, rssKB: 1, name: "node")
        #expect(t.feed([node], now: t0).isEmpty)
        #expect(t.feed([node], now: t0.addingTimeInterval(59)).isEmpty)
        let fired = t.feed([node], now: t0.addingTimeInterval(60))
        #expect(fired.count == 1 && fired[0].0.pid == 412)
        #expect(t.feed([node], now: t0.addingTimeInterval(70)).isEmpty)       // once per streak
        // Cools down, then heats up again: a new streak.
        #expect(t.feed([Stats.Process(pid: 412, cpu: 20, rssKB: 1, name: "node")], now: t0.addingTimeInterval(80)).isEmpty)
        #expect(t.feed([node], now: t0.addingTimeInterval(90)).isEmpty)
        #expect(t.feed([node], now: t0.addingTimeInterval(150)).count == 1)
    }
}

@Suite struct PortScanTests {
    static let sample = """
    p412
    cnode
    f22
    n*:3000
    f23
    n[::1]:3000
    p530
    cnode
    f19
    n127.0.0.1:5173
    p88
    cControlCe
    f7
    n*:5000
    f8
    n*:7000
    p91
    cjava
    n*:8080
    p95
    crapportd
    n*:49158
    """

    @Test func parsesAndDedupes() {
        let all = PortScan.parse(Self.sample)
        #expect(all.map(\.port) == [3000, 5000, 5173, 7000, 8080, 49158])
        #expect(all.first == PortScan.Listener(port: 3000, pid: 412, command: "node"))
    }

    @Test func filtersSystemPorts() {
        let dev = PortScan.devServers(PortScan.parse(Self.sample))
        #expect(dev.map(\.port) == [3000, 5173, 8080])
        #expect(PortScan.devServers(PortScan.parse(Self.sample), extraIgnored: ["java"]).map(\.port) == [3000, 5173])
    }

    @Test func announcesOnlyNewPorts() {
        let a = [PortScan.Listener(port: 3000, pid: 1, command: "node")]
        let b = a + [PortScan.Listener(port: 5173, pid: 2, command: "node")]
        #expect(PortScan.newPorts(previous: nil, current: b).isEmpty)
        #expect(PortScan.newPorts(previous: a, current: b).map(\.port) == [5173])
    }
}
