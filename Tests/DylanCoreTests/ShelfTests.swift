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
