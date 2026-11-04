import CoreGraphics
import Testing
@testable import DylanCore

@Suite struct RecordingTests {
    @Test func sourceRectIsDisplayLocalTopLeft() {
        // Primary 1512×982 screen; the region sits 100 pt from the left and 200 pt from the top.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(ScreenRecording.sourceRect(CGRect(x: 100, y: 482, width: 400, height: 300), screen: screen)
                == CGRect(x: 100, y: 200, width: 400, height: 300))
        // A second display to the right and lower: offsets are relative to that display.
        let right = CGRect(x: 1512, y: -100, width: 1920, height: 1080)
        #expect(ScreenRecording.sourceRect(CGRect(x: 1612, y: 780, width: 200, height: 100), screen: right)
                == CGRect(x: 100, y: 100, width: 200, height: 100))
    }

    @Test func pixelSizeIsEvenAndFitsTheEncoder() {
        #expect(ScreenRecording.pixelSize(points: CGSize(width: 1512, height: 982), scale: 2) == (3024, 1964))
        #expect(ScreenRecording.pixelSize(points: CGSize(width: 401, height: 301), scale: 1) == (400, 300))
        // A 5K display at 2x would be 5120 px wide: shrunk to 4096 keeping the ratio.
        let k = ScreenRecording.pixelSize(points: CGSize(width: 2560, height: 1440), scale: 2)
        #expect(k.width == 4096 && k.height == 2304)
        #expect(ScreenRecording.pixelSize(points: CGSize(width: 0.4, height: 0.4), scale: 1) == (2, 2))
    }
}
