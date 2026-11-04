import CoreGraphics
import Foundation

/// Screen recording (FR-94): the geometry and sizing rules, kept free of ScreenCaptureKit so they can be tested.
public enum ScreenRecording {
    /// H.264 encoders refuse frames larger than this on either side.
    public static let maxDimension = 4096

    /// A region in global AppKit points (origin bottom-left of the primary screen) → ScreenCaptureKit's
    /// `sourceRect`: points relative to the display, origin top-left.
    public static func sourceRect(_ region: CGRect, screen: CGRect) -> CGRect {
        CGRect(x: region.minX - screen.minX, y: screen.maxY - region.maxY, width: region.width, height: region.height).integral
    }

    /// Output size in pixels: the region at `scale`, shrunk to fit `maxDimension`, rounded down to even numbers
    /// (4:2:0 video needs even sides).
    public static func pixelSize(points: CGSize, scale: CGFloat, maxDimension: Int = maxDimension) -> (width: Int, height: Int) {
        var w = points.width * scale, h = points.height * scale
        let fit = min(1, CGFloat(maxDimension) / max(w, h, 1))
        w *= fit; h *= fit
        func even(_ v: CGFloat) -> Int { max(2, Int(v) / 2 * 2) }
        return (even(w), even(h))
    }
}
