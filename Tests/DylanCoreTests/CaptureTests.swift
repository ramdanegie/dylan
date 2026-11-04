import CoreGraphics
import Foundation
import Testing
@testable import DylanCore

@Suite struct CaptureSelectionTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func dragAnyDirection() {
        #expect(CaptureSelection.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 250), bounds: screen) == CGRect(x: 100, y: 100, width: 200, height: 150))
        #expect(CaptureSelection.rect(from: CGPoint(x: 300, y: 250), to: CGPoint(x: 100, y: 100), bounds: screen) == CGRect(x: 100, y: 100, width: 200, height: 150))
    }

    @Test func modifiers() {
        // ⇧ square, keeping the drag direction.
        #expect(CaptureSelection.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 150), lockRatio: 1, bounds: screen) == CGRect(x: 100, y: 100, width: 200, height: 200))
        #expect(CaptureSelection.rect(from: CGPoint(x: 300, y: 300), to: CGPoint(x: 250, y: 100), lockRatio: 1, bounds: screen) == CGRect(x: 100, y: 100, width: 200, height: 200))
        // ⌥ from center.
        #expect(CaptureSelection.rect(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 600, y: 550), fromCenter: true, bounds: screen) == CGRect(x: 400, y: 450, width: 200, height: 100))
        // Clamped to the screen.
        #expect(CaptureSelection.rect(from: CGPoint(x: 1400, y: 900), to: CGPoint(x: 1700, y: 1100), bounds: screen) == CGRect(x: 1400, y: 900, width: 112, height: 82))
    }

    @Test func nudgeAndPixels() {
        let r = CGRect(x: 0, y: 10, width: 100, height: 100)
        #expect(CaptureSelection.nudge(r, dx: -1, dy: 0, bounds: screen).minX == 0)            // stays on screen
        #expect(CaptureSelection.nudge(r, dx: 1, dy: 1, bounds: screen).origin == CGPoint(x: 1, y: 11))
        // Bottom-left points → top-left pixels at 2×.
        #expect(CaptureSelection.pixelRect(CGRect(x: 10, y: 882, width: 100, height: 50), screen: screen, scale: 2) == CGRect(x: 20, y: 100, width: 200, height: 100))
        #expect(CaptureSelection.isClick(CGRect(x: 5, y: 5, width: 2, height: 1)))
    }
}

@Suite struct CaptureStoreTests {
    @Test func namesAndRetention() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        let d = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9, minute: 41))!
        #expect(CaptureStore.fileName(d, calendar: cal) == "Dylan 2026-11-04 09.41.png")
        #expect(CaptureStore.fileName(d, ext: "jpg", calendar: cal).hasSuffix(".jpg"))
        let old = d.addingTimeInterval(-31 * 86_400), fresh = d.addingTimeInterval(-29 * 86_400)
        #expect(CaptureStore.expired([("a", old), ("b", fresh)], now: d, days: 30) == ["a"])
        #expect(CaptureStore.expired([("a", old)], now: d, days: 0).isEmpty)
        #expect(CaptureStore.summary(count: 142, bytes: 90_177_536) == (142, 86))
    }
}

@Suite struct ScrollStitchTests {
    /// A "page" of unique rows; a frame is a window of `h` rows starting at `top`, with an optional fixed header.
    func frame(_ page: [UInt64], top: Int, h: Int, header: [UInt64] = []) -> [UInt64] {
        header + Array(page[top..<(top + h - header.count)])
    }

    @Test func findsTheScroll() {
        let page = (0..<2000).map { UInt64($0) * 2654435761 }
        let a = frame(page, top: 0, h: 400), b = frame(page, top: 120, h: 400)
        #expect(ScrollStitch.shift(a, b) == 120)
        #expect(ScrollStitch.newRows(height: 400, shift: 120) == 280..<400)
        #expect(ScrollStitch.shift(a, a) == nil)                                      // did not move
        #expect(ScrollStitch.shift(a, frame(page, top: 900, h: 400)) == nil)          // jumped too far
    }

    @Test func stickyHeaderIsNotRepeated() {
        let page = (0..<2000).map { UInt64($0) * 2654435761 + 7 }
        let header: [UInt64] = [1, 2, 3, 4, 5, 6, 7, 8]
        let a = frame(page, top: 0, h: 400, header: header), b = frame(page, top: 100, h: 400, header: header)
        let sticky = ScrollStitch.stickyRows(a, b)
        #expect(sticky == 8)
        #expect(ScrollStitch.shift(a, b, sticky: sticky) == 100)
        #expect(ScrollStitch.stickyRows(a, a) == 0)
    }
}
