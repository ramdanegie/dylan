import AppKit
import DylanCore
import SwiftUI

/// Tokens from the design handoff (§4 "Token").
nonisolated enum DY {
    static let shape = Color.black                       // always, Light & Dark
    static let fg = Color.white.opacity(0.85)            // running
    static let fg2 = Color.white.opacity(0.55)
    static let ok = Color(nsColor: .systemGreen)
    static let fail = Color(nsColor: .systemRed)
    static let action = Color(nsColor: .systemYellow)    // amber
    static let info = Color(nsColor: .systemBlue)
    static let camDot = Color(nsColor: .systemGreen)
    static let micDot = Color(nsColor: .systemOrange)
    static let control = Color.white.opacity(0.12)
    static let controlHover = Color.white.opacity(0.20)
    static let controlPressed = Color.white.opacity(0.08)
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let reduced = Animation.easeInOut(duration: 0.2)
    static let fadeIn = Animation.easeOut(duration: 0.14).delay(0.06)
    static let fadeOut = Animation.easeOut(duration: 0.10)
    static let shoulder: CGFloat = 8

    static func font(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight) }
    static let mono = Font.system(size: 11, design: .monospaced)

    static func color(for state: ActivityState) -> Color {
        switch state {
        case .running, .ambient: return fg
        case .success: return ok
        case .failure: return fail
        case .needsAction: return action
        case .info: return info
        }
    }

    /// Dominant artwork colour, brightened until it reads on black (contrast ≥ 4.5:1).
    static func accent(_ image: NSImage?) -> Color {
        guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return fg }
        let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0)
        guard let small else { return fg }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
        rep.draw(in: NSRect(x: 0, y: 0, width: 8, height: 8))
        NSGraphicsContext.restoreGraphicsState()
        var best: NSColor?, bestScore: CGFloat = -1
        for x in 0..<8 { for y in 0..<8 {
            guard let c = small.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            let score = c.saturationComponent * c.brightnessComponent
            if score > bestScore { bestScore = score; best = c }
        } }
        guard let b = best, bestScore > 0.08 else { return fg }
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
        b.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
        // Relative luminance ≥ 0.18 gives ≥ 4.5:1 against black.
        var color = NSColor(hue: hue, saturation: min(sat, 0.75), brightness: max(bri, 0.7), alpha: 1)
        while luminance(color) < 0.18, sat > 0.1 {
            sat -= 0.1
            color = NSColor(hue: hue, saturation: min(sat, 0.75), brightness: 1, alpha: 1)
        }
        return Color(nsColor: color)
    }

    private static func luminance(_ c: NSColor) -> CGFloat {
        func ch(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = c.usingColorSpace(.sRGB) ?? c
        return 0.2126 * ch(r.redComponent) + 0.7152 * ch(r.greenComponent) + 0.0722 * ch(r.blueComponent)
    }
}

/// Black island that hangs from the top edge: concave shoulders on top, continuous corners below.
nonisolated struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var shoulder: CGFloat = DY.shoulder

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in r: CGRect) -> Path {
        let s = min(shoulder, r.width / 4)
        let body = r.insetBy(dx: s, dy: 0)
        let br = min(bottomRadius, body.width / 2, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: body.maxX, y: r.minY + s), control: CGPoint(x: body.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: body.maxX, y: r.maxY - br))
        p.addCurve(to: CGPoint(x: body.maxX - br, y: r.maxY),
                   control1: CGPoint(x: body.maxX, y: r.maxY - br * 0.45),
                   control2: CGPoint(x: body.maxX - br * 0.45, y: r.maxY))
        p.addLine(to: CGPoint(x: body.minX + br, y: r.maxY))
        p.addCurve(to: CGPoint(x: body.minX, y: r.maxY - br),
                   control1: CGPoint(x: body.minX + br * 0.45, y: r.maxY),
                   control2: CGPoint(x: body.minX, y: r.maxY - br * 0.45))
        p.addLine(to: CGPoint(x: body.minX, y: r.minY + s))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY), control: CGPoint(x: body.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Floating pill for screens without a notch: every corner rounded.
nonisolated struct PillShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat { get { radius } set { radius = newValue } }
    func path(in r: CGRect) -> Path { Path(roundedRect: r, cornerRadius: min(radius, r.height / 2), style: .continuous) }
}

/// Content transition from the handoff: fade + blur, never scale.
struct BlurFade: ViewModifier {
    var r: CGFloat
    var o: Double
    func body(content: Content) -> some View { content.blur(radius: r).opacity(o) }
}

extension AnyTransition {
    static var dyContent: AnyTransition {
        .asymmetric(insertion: .modifier(active: BlurFade(r: 4, o: 0), identity: BlurFade(r: 0, o: 1)).animation(DY.fadeIn),
                    removal: .modifier(active: BlurFade(r: 4, o: 0), identity: BlurFade(r: 0, o: 1)).animation(DY.fadeOut))
    }
}

/// Capsule button inside the notch (design "Tombol di dalam notch").
struct NotchButton: View {
    /// confirm = green (accept a call, design D28): the button follows the meaning of the action.
    enum Kind { case normal, primaryAction, primaryNeutral, destructive, confirm, quiet }
    var title: String
    var kind: Kind = .normal
    var height: CGFloat = 24
    var action: () -> Void
    @StateBox private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DY.font(12, kind == .quiet ? .regular : (kind == .normal ? .medium : .semibold)))
                .foregroundStyle(foreground)
                .padding(.horizontal, 10)
                .frame(height: height)
                .background(Capsule().fill(background))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .onHover { hover = $0 }
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        switch kind {
        case .primaryAction: return .black
        case .primaryNeutral: return .black
        case .destructive, .confirm: return .white
        case .quiet: return DY.fg2
        case .normal: return .white
        }
    }

    private var background: Color {
        switch kind {
        case .primaryAction: return hover ? DY.action.opacity(0.85) : DY.action
        case .primaryNeutral: return hover ? .white.opacity(0.85) : .white
        case .destructive: return hover ? DY.fail.opacity(0.85) : DY.fail
        case .confirm: return hover ? DY.ok.opacity(0.85) : DY.ok
        case .quiet: return .clear
        case .normal: return hover ? DY.controlHover : DY.control
        }
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1).opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// With Command Line Tools only, the macOS 27 SDK resolves `@State` to a macro whose plugin ships with Xcode.
/// The property-wrapper type itself works fine through an alias.
typealias StateBox = SwiftUI.State
