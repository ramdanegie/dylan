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
