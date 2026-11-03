import Foundation
import Testing
@testable import DylanCore

@Suite struct ShelfTests {
    let t0 = Date(timeIntervalSince1970: 6_000_000)

    @Test func addMovesDuplicatesToFront() {
        var s = Shelf()
        s.add(["/a/one.png", "/a/two.sql"], now: t0)
        #expect(s.items.map(\.name) == ["one.png", "two.sql"])
        s.add(["/a/../a/two.sql"], now: t0)
        #expect(s.items.map(\.name) == ["two.sql", "one.png"])
        #expect(s.items[0].ext == "SQL")
    }

    @Test func limitAndMissing() {
        var s = Shelf(); s.limit = 2
        s.add(["/x/1", "/x/2", "/x/3"], now: t0)
        #expect(s.items.count == 2)
        let gone = s.missing { $0 != "/x/1" }
        #expect(gone == Set(s.items.filter { $0.path == "/x/1" }.map(\.id)))   // "/x/1" no longer exists
    }

    @Test func zipNames() {
        var s = Shelf()
        s.add(["/d/report.pdf"], now: t0)
        #expect(Shelf.zipName(for: s.items, now: t0) == "report.zip")
        s.add(["/d/a.png"], now: t0)
        #expect(Shelf.zipName(for: s.items, now: t0).hasPrefix("Shelf "))
        #expect(Shelf.zipName(for: s.items, now: t0).hasSuffix(".zip"))
    }
}

@Suite struct ShakeTests {
    @Test func shakeDetected() {
        var s = ShakeDetector()
        let xs: [CGFloat] = [100, 140, 100, 140, 100]
        var fired = false
        for (i, x) in xs.enumerated() { fired = s.feed(x: x, time: Double(i) * 0.1) || fired }
        #expect(fired)
    }

    @Test func normalDragIsNotAShake() {
        var s = ShakeDetector()
        var fired = false
        for i in 0..<20 { fired = s.feed(x: CGFloat(i * 15), time: Double(i) * 0.05) || fired }   // straight line
        #expect(!fired)
        var slow = ShakeDetector()
        for (i, x) in ([100, 140, 100, 140, 100] as [CGFloat]).enumerated() { fired = slow.feed(x: x, time: Double(i) * 0.4) || fired }
        #expect(!fired)                                                                           // too slow
        var small = ShakeDetector()
        for (i, x) in ([100, 110, 100, 110, 100] as [CGFloat]).enumerated() { fired = small.feed(x: x, time: Double(i) * 0.1) || fired }
        #expect(!fired)                                                                           // jitter, not a shake
    }
}
