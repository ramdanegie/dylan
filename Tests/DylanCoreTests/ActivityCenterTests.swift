import Foundation
import Testing
@testable import DylanCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func act(_ id: String, _ p: Priority, _ state: ActivityState = .running, at t: TimeInterval = 0) -> Activity {
    Activity(id: id, kind: .script, priority: p, state: state, symbol: "terminal", label: id,
             startedAt: t0.addingTimeInterval(t))
}

@Suite struct ActivityCenterTests {
    @Test func slotsPickHighestPriorityThenNewest() {
        var c = ActivityCenter()
        c.upsert(act("music", .p3))
        c.upsert(act("cmd", .p2, at: 1))
        c.upsert(act("agent", .p2, at: 2))
        #expect(c.slots().map(\.id) == ["agent", "cmd"])
        #expect(c.queued().map(\.id) == ["music"])
        c.upsert(act("perm", .p0, .needsAction, at: 3))
        #expect(c.slots().map(\.id) == ["perm", "agent"])
    }

    @Test func singleSlotWhenDuoOff() {
        var cfg = ActivityCenter.Config(); cfg.maxSlots = 1
        var c = ActivityCenter(config: cfg)
        c.upsert(act("a", .p2)); c.upsert(act("b", .p3))
        #expect(c.slots().map(\.id) == ["a"])
    }

    @Test func fullscreenShowsOnlyP0() {
        var c = ActivityCenter()
        c.upsert(act("cmd", .p2)); c.upsert(act("music", .p3))
        #expect(c.slots(fullscreen: true).isEmpty)
        c.upsert(act("meeting", .p0, .needsAction))
        #expect(c.slots(fullscreen: true).map(\.id) == ["meeting"])
    }

    @Test func successHoldsFiveSecondsFailureEight() {
        var c = ActivityCenter()
        c.upsert(act("ok", .p2)); c.upsert(act("bad", .p2))
        c.finish("ok", success: true, now: t0)
        c.finish("bad", success: false, now: t0)
        #expect(c.activities["ok"]?.priority == .p1)
        #expect(c.tick(now: t0.addingTimeInterval(4.9)).isEmpty)
        #expect(c.tick(now: t0.addingTimeInterval(5)) == ["ok"])
        #expect(c.tick(now: t0.addingTimeInterval(7.9)).isEmpty)
        #expect(c.tick(now: t0.addingTimeInterval(8)) == ["bad"])
        #expect(c.history.map(\.activity.id) == ["bad", "ok"])
    }

    @Test func hoverPausesResultTimer() {
        var c = ActivityCenter()
        c.upsert(act("ok", .p2))
        c.finish("ok", success: true, now: t0)
        c.setHoldPaused(true, now: t0.addingTimeInterval(2))
        #expect(c.tick(now: t0.addingTimeInterval(20)).isEmpty)
        c.setHoldPaused(false, now: t0.addingTimeInterval(12))   // paused 10 s
        #expect(c.tick(now: t0.addingTimeInterval(14.9)).isEmpty)
        #expect(c.tick(now: t0.addingTimeInterval(15)) == ["ok"])
    }

    @Test func p0NeverExpires() {
        var c = ActivityCenter()
        var a = act("perm", .p0, .needsAction); a.endedAt = t0
        c.post(a, now: t0)
        #expect(c.tick(now: t0.addingTimeInterval(3600)).isEmpty)
    }

    @Test func historyKeepsTwentyAndSkipsAmbient() {
        var c = ActivityCenter()
        for i in 0..<25 { c.post(act("n\(i)", .p1, .success, at: Double(i)), now: t0.addingTimeInterval(Double(i))) }
        c.post(act("music", .p3, .success), now: t0)
        c.tick(now: t0.addingTimeInterval(100))
        #expect(c.history.count == 20)
        #expect(!c.history.contains { $0.activity.id == "music" })
    }

    @Test func upsertReplacesAndClearsEnd() {
        var c = ActivityCenter()
        c.upsert(act("x", .p2, at: 0))
        var later = act("x", .p2, at: 50); later.label = "new"; later.endedAt = t0
        c.upsert(later)
        #expect(c.activities["x"]?.startedAt == t0.addingTimeInterval(50))
        #expect(c.activities["x"]?.label == "new")
        #expect(c.activities["x"]?.endedAt == nil)   // a running activity cannot carry a result timer
    }
}

@Suite struct NotchGeometryTests {
    // MacBook Pro 14": 1512 × 982 pt, notch ≈ 185 pt wide, 32 pt tall.
    let g = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                          leftAuxWidth: 663.5, rightAuxWidth: 663.5)

    @Test func notchFromSafeArea() {
        #expect(g.hasNotch)
        #expect(g.notch == CGSize(width: 185, height: 32))
        #expect(g.centerX == 756)
    }

    @Test func stateSizes() {
        #expect(g.size(for: .closed) == g.notch)
        #expect(g.size(for: .compact) == CGSize(width: 185 + 192, height: 32))
        #expect(g.size(for: .peek) == CGSize(width: 372, height: 76))
        #expect(g.size(for: .expanded).width == 640)
        #expect(g.size(for: .expanded, wide: true, expandedHeight: 999).height == 380)
        #expect(g.size(for: .expanded, expandedHeight: 10).height == 218)
        #expect(g.radius(for: .expanded) == 30)
    }

    @Test func shapeHangsFromTopEdge() {
        let f = g.shapeFrame(for: .compact)
        #expect(f.maxY == 982)
        #expect(f.midX == 756)
        #expect(g.panelFrame.maxY == 982)
        #expect(g.panelFrame.contains(g.shapeFrame(for: .expanded, wide: true, expandedHeight: 380)))
    }

    @Test func pillWithoutNotch() {
        let p = NotchGeometry(screen: CGRect(x: 1512, y: 0, width: 2560, height: 1440), safeAreaTop: 0,
                              leftAuxWidth: nil, rightAuxWidth: nil)
        #expect(!p.hasNotch)
        #expect(p.centerX == CGFloat(2792))
        #expect(p.shapeFrame(for: .compact).maxY == CGFloat(1434))
        #expect(p.radius(for: .compact) == 16)
    }
}
