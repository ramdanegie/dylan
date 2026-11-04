import CoreGraphics
import Foundation

/// Studio & editor presets (FR-92/93, design D41/D44), taken from the design file. Colors are hex strings so
/// the app can render them with SwiftUI and export with ImageRenderer.
public enum Beautify {
    public struct Stop: Equatable, Sendable { public var color: String; public var at: Double }
    /// A radial blob of a mesh gradient: center (0…1), color, radius as a fraction of the larger side.
    public struct Blob: Equatable, Sendable { public var x: Double, y: Double; public var color: String; public var radius: Double }

    public enum Fill: Equatable, Sendable {
        case transparent
        case solid(String)
        /// CSS angle: 0° points up, 90° right, 135° to the bottom right.
        case linear(angle: Double, stops: [Stop])
        case mesh(base: String, blobs: [Blob])
        /// Colors taken from the screenshot itself (design "Dari gambar").
        case fromImage
    }

    public struct Background: Equatable, Sendable { public var name: String; public var fill: Fill }

    static func lin(_ a: Double, _ s: [(String, Double)]) -> Fill { .linear(angle: a, stops: s.map { Stop(color: $0.0, at: $0.1) }) }
    static func mesh(_ base: String, _ b: [(Double, Double, String, Double)]) -> Fill {
        .mesh(base: base, blobs: b.map { Blob(x: $0.0, y: $0.1, color: $0.2, radius: $0.3) })
    }

    /// Studio backgrounds (D44), in design order.
    public static let backgrounds: [Background] = [
        .init(name: "Mesh senja", fill: mesh("#C6A6D6", [(0.12, 0.18, "#DFF7EE", 0.45), (0.48, 0.08, "#8A7FE0", 0.48), (0.86, 0.26, "#C9705E", 0.46),
                                                       (0.18, 0.92, "#D8C6F7", 0.50), (0.92, 0.92, "#F7DDAA", 0.46)])),
        .init(name: "Mesh laut", fill: mesh("#4A7FD9", [(0.10, 0.10, "#A8F0FF", 0.45), (0.90, 0.20, "#3E6BFF", 0.50), (0.30, 0.90, "#5DE0C0", 0.50),
                                                      (0.85, 0.85, "#1B2A7A", 0.50)])),
        .init(name: "Mesh mint", fill: mesh("#A9E5CC", [(0.15, 0.15, "#F4FFF8", 0.45), (0.85, 0.20, "#9BE7C4", 0.50), (0.20, 0.85, "#C9F2E0", 0.50),
                                                      (0.85, 0.85, "#6CC9A8", 0.50)])),
        .init(name: "Mesh malam", fill: mesh("#121433", [(0.20, 0.20, "#3A3F8F", 0.50), (0.80, 0.30, "#7A2E7A", 0.50), (0.50, 0.95, "#0E7C86", 0.50)])),
        .init(name: "Mesh persik", fill: mesh("#FFB9A0", [(0.10, 0.20, "#FFE3C2", 0.45), (0.80, 0.15, "#FF9DB0", 0.50), (0.30, 0.90, "#FFC78A", 0.50),
                                                        (0.90, 0.85, "#F7748A", 0.45)])),
        .init(name: "Senja", fill: lin(135, [("#FFB36B", 0), ("#FF6B8A", 1)])),
        .init(name: "Laut", fill: lin(135, [("#4FACFE", 0), ("#2B5CE6", 1)])),
        .init(name: "Aurora", fill: lin(135, [("#3BE0A8", 0), ("#2A7BE4", 0.6), ("#5B3FD9", 1)])),
        .init(name: "Ungu", fill: lin(135, [("#C471F5", 0), ("#7A5CFF", 1)])),
        .init(name: "Jeruk", fill: lin(160, [("#FFD36B", 0), ("#FF8A3D", 0.55), ("#E8522E", 1)])),
        .init(name: "Dari gambar", fill: .fromImage),
        .init(name: "Putih", fill: .solid("#FFFFFF")),
        .init(name: "Kertas", fill: .solid("#F1EEE7")),
        .init(name: "Grafit", fill: .solid("#1E2129")),
        .init(name: "Transparan", fill: .transparent),
    ]

    /// Editor backgrounds (D41).
    public static let editorBackgrounds: [Background] = [
        .init(name: "Transparan", fill: .transparent), .init(name: "Putih", fill: .solid("#FFFFFF")), .init(name: "Grafit", fill: .solid("#1E2129")),
        .init(name: "Senja", fill: lin(135, [("#FFB36B", 0), ("#FF6B8A", 1)])), .init(name: "Laut", fill: lin(135, [("#4FACFE", 0), ("#2B5CE6", 1)])),
        .init(name: "Aurora", fill: lin(135, [("#3BE0A8", 0), ("#2A7BE4", 0.6), ("#5B3FD9", 1)])),
        .init(name: "Ungu", fill: lin(135, [("#C471F5", 0), ("#7A5CFF", 1)])),
        .init(name: "Jeruk", fill: lin(160, [("#FFD36B", 0), ("#FF8A3D", 0.55), ("#E8522E", 1)])),
        .init(name: "Mint", fill: lin(135, [("#D4FCE3", 0), ("#8FE3C1", 1)])),
        .init(name: "Malam", fill: mesh("#05070E", [(0.5, 0.0, "#2A3B6B", 0.9), (0.5, 0.3, "#0E1530", 0.7)])),
    ]

    /// Window chrome around the screenshot (D44 "Bingkai").
    public enum Frame: String, CaseIterable, Sendable {
        case none, mac, macDark, browser, browserDark, glass
        public var name: String {
            switch self {
            case .none: "Tanpa"; case .mac: "macOS"; case .macDark: "macOS gelap"
            case .browser: "Browser"; case .browserDark: "Browser gelap"; case .glass: "Kaca"
            }
        }
        /// Title bar height in points at 1×.
        public var barHeight: CGFloat {
            switch self { case .none, .glass: 0; case .mac, .macDark: 30; case .browser, .browserDark: 34 }
        }
        public var isDark: Bool { self == .macDark || self == .browserDark }
        public var hasAddressBar: Bool { self == .browser || self == .browserDark }
        public var barColor: String { isDark ? "#232428" : "#F2F1EF" }
        /// Glass draws a translucent border instead of a bar.
        public var glassBorder: CGFloat { self == .glass ? 10 : 0 }
    }

    public struct ShadowLayer: Equatable, Sendable { public var x, y, blur: CGFloat; public var color: String; public var opacity: Double }
    public struct Shadow: Equatable, Sendable { public var name: String; public var layers: [ShadowLayer] }

    public static let shadows: [Shadow] = [
        .init(name: "Tanpa", layers: []),
        .init(name: "Lembut", layers: [.init(x: 0, y: 18, blur: 44, color: "#000000", opacity: 0.22)]),
        .init(name: "Melayang", layers: [.init(x: 0, y: 50, blur: 100, color: "#000000", opacity: 0.45), .init(x: 0, y: 12, blur: 24, color: "#000000", opacity: 0.2)]),
        .init(name: "Tajam", layers: [.init(x: 14, y: 14, blur: 0, color: "#000000", opacity: 0.85)]),
        .init(name: "Glow", layers: [.init(x: 0, y: 30, blur: 90, color: "#8C5AE6", opacity: 0.6)]),
    ]

    public struct Ratio: Equatable, Sendable { public var name: String; public var value: Double?; public var glyph: String }
    /// Auto = follow the content. X and LinkedIn are social presets (D41: X 16:9, Instagram 1:1 & 4:5, LinkedIn).
    public static let ratios: [Ratio] = [
        .init(name: "Auto", value: nil, glyph: ""), .init(name: "16:9", value: 16.0 / 9, glyph: ""), .init(name: "4:3", value: 4.0 / 3, glyph: ""),
        .init(name: "1:1", value: 1, glyph: ""), .init(name: "4:5", value: 4.0 / 5, glyph: ""), .init(name: "9:16", value: 9.0 / 16, glyph: ""),
        .init(name: "X post", value: 16.0 / 9, glyph: "𝕏"), .init(name: "LinkedIn", value: 1.91, glyph: "in"),
    ]

    /// 3D layouts (D44 "Tata letak"): rotation in degrees and where the picture sits (0.5 = centered).
    public struct Layout: Equatable, Sendable {
        public var name: String
        public var rotateX, rotateY, rotateZ: Double
        public var anchorX, anchorY: Double
    }
    public static let layouts: [Layout] = [
        .init(name: "Lurus", rotateX: 0, rotateY: 0, rotateZ: 0, anchorX: 0.5, anchorY: 0.5),
        .init(name: "Miring kiri", rotateX: 6, rotateY: 20, rotateZ: 0, anchorX: 0.5, anchorY: 0.5),
        .init(name: "Miring kanan", rotateX: 6, rotateY: -20, rotateZ: 0, anchorX: 0.5, anchorY: 0.5),
        .init(name: "Isometrik", rotateX: 48, rotateY: 0, rotateZ: -30, anchorX: 0.5, anchorY: 0.5),
        .init(name: "Dari bawah", rotateX: 0, rotateY: 0, rotateZ: 0, anchorX: 0.5, anchorY: 0.78),
        .init(name: "Zoom pojok", rotateX: 0, rotateY: 0, rotateZ: 0, anchorX: 0.78, anchorY: 0.74),
    ]

    /// The picture with its frame, then padding on every side, then grown to the ratio (never cropped).
    public static func canvasSize(content: CGSize, frame: Frame, padding: CGFloat, ratio: Double?) -> CGSize {
        let framed = CGSize(width: content.width + frame.glassBorder * 2, height: content.height + frame.barHeight + frame.glassBorder * 2)
        var w = framed.width + padding * 2, h = framed.height + padding * 2
        if let r = ratio, r > 0 {
            if w / h < r { w = (h * r).rounded() } else { h = (w / r).rounded() }
        }
        return CGSize(width: w, height: h)
    }

    /// "#RRGGBB" → 0…1 components (nil for anything else).
    public static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}
