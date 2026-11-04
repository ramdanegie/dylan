import AppKit
import SwiftUI

/// Design D50 "Settings yang lebih tenang": warm neutrals, Cermin's teal, a drawn banner per page and serif titles.
/// Shared by Settings and Dylan's other windows (Storage, updates, capture history).
enum Art {
    static func hex(_ v: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }
    static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
    private static func c(_ light: NSColor, _ dark: NSColor) -> Color { Color(nsColor: dynamic(light, dark)) }

    static let contentNS = dynamic(hex(0xF7F6F3), hex(0x191B1E))
    static let content = Color(nsColor: contentNS)
    static let side = c(hex(0xEFECE6), hex(0x1E2024))
    static let card = c(.white, hex(0x222529))
    static let line = c(.black.withAlphaComponent(0.07), .white.withAlphaComponent(0.07))
    static let ink2 = c(hex(0x6B6B70), hex(0x9C9EA3))
    static let ink3 = c(hex(0x8E8E93), hex(0x76787D))
    static let ctrl = c(hex(0xECEAE5), hex(0x2E3135))
    /// Cermin teal; lighter in dark mode so it keeps its contrast.
    static let accentNS = dynamic(hex(0x00838A), hex(0x23A7A8))
    static let accent = Color(nsColor: accentNS)
    static let selected = c(.white, .white.withAlphaComponent(0.08))
    static let bannerTop = c(hex(0xF2F0EB), hex(0x1F2226))
    static let bannerLow = c(hex(0xE4E4E3), hex(0x16181B))
    static let horizon = c(.white.withAlphaComponent(0.7), .white.withAlphaComponent(0.07))
    static let ring = c(.black.withAlphaComponent(0.045), .white.withAlphaComponent(0.05))

    /// Orb colours: teal, sand and deep teal match Cermin; the others differ only in hue.
    enum Orb {
        static let teal: UInt32 = 0x93D9D6, sand: UInt32 = 0xF2C9AA, lilac: UInt32 = 0xC9C2F0, sky: UInt32 = 0xA9CCF2
        static let green: UInt32 = 0xBFE0C4, rose: UInt32 = 0xF2B8C2, butter: UInt32 = 0xEBDDB8
    }

    /// 128 px of grey noise for the banner grain, made once.
    static let noise: CGImage? = {
        var bytes = [UInt8](repeating: 0, count: 128 * 128)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return CGDataProvider(data: Data(bytes) as CFData).flatMap {
            CGImage(width: 128, height: 128, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }()
}

/// The page banner (D50): Dylan's island on the horizon at 62 %, two orbs behind it, their reflection, concentric
/// rings and grain. Drawn, not an image, so it follows Light/Dark and each page's colours. Purely decorative.
struct ArtBanner: View {
    var orbs: (UInt32, UInt32)
    /// Orb centres as a fraction of the width.
    var x: (CGFloat, CGFloat)
    /// The page's small status inside the island ("68°", "1440×900").
    var island: String
    var height: CGFloat = 184
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, k = h / 184, horizon = h * 0.62
            ZStack(alignment: .topLeading) {
                Art.bannerTop
                ZStack(alignment: .topLeading) {
                    orb(orbs.0, 380, 260).position(x: w * x.0, y: 100 * k)
                    orb(orbs.1, 340, 240).position(x: w * x.1, y: 70 * k)
                }
                .frame(width: w, height: horizon, alignment: .topLeading).clipped()
                .opacity(scheme == .dark ? 0.45 : 0.85)
                ZStack(alignment: .topLeading) {
                    Art.bannerLow
                    // The reflection: the same orbs and island mirrored, faded out by 55 %.
                    ZStack(alignment: .topLeading) {
                        orb(orbs.0, 380, 260).position(x: w * x.0, y: 40 * k)
                        orb(orbs.1, 340, 240).position(x: w * x.1, y: 50 * k)
                        Capsule().fill(Color(nsColor: Art.hex(0x0B0B0C))).frame(width: 172, height: 40).position(x: w / 2, y: 6 * k + 20)
                    }
                    .opacity(0.28)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .clear, location: 0.55)], startPoint: .top, endPoint: .bottom))
                }
                .frame(width: w, height: h - horizon, alignment: .topLeading).clipped()
                .offset(y: horizon)
                Rectangle().fill(Art.horizon).frame(width: w, height: 1).offset(y: horizon)
                ForEach([150, 250, 370] as [CGFloat], id: \.self) { d in
                    Circle().strokeBorder(Art.ring, lineWidth: 1).frame(width: d, height: d).position(x: w / 2, y: 88 * k)
                }
                pill.position(x: w / 2, y: 88 * k)
                if let noise = Art.noise {
                    Image(decorative: noise, scale: 2).resizable(resizingMode: .tile)
                        .blendMode(.overlay).opacity(0.3).allowsHitTesting(false)
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Art.line, lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private func orb(_ color: UInt32, _ w: CGFloat, _ h: CGFloat) -> some View {
        Ellipse()
            .fill(EllipticalGradient(colors: [Color(nsColor: Art.hex(color)), Color(nsColor: Art.hex(color, 0))], center: .center,
                                     startRadiusFraction: 0, endRadiusFraction: 0.5))
            .frame(width: w, height: h)
    }

    private var pill: some View {
        let glow = Color(nsColor: Art.hex(0x6FE6D2))
        return HStack(spacing: 6) {
            SwiftUI.Text(island).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white.opacity(0.88))
                .lineLimit(1).minimumScaleFactor(0.7).monospacedDigit()
            Spacer(minLength: 0)
            Circle().fill(glow).frame(width: 9, height: 9).shadow(color: glow.opacity(0.55), radius: 5)
        }
        .padding(.leading, 16).padding(.trailing, 14)
        .frame(width: 172, height: 40)
        .background(Capsule().fill(Color(nsColor: Art.hex(0x0B0B0C))))
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 10)
    }
}

/// Mono eyebrow, a New York title with one italic word, and a line of SF Pro below (D50).
struct ArtTitle: View {
    var eyebrow: String
    var title: String
    var italic: String
    var detail: String?
    var size: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SwiftUI.Text(eyebrow).font(.system(size: 10.5, design: .monospaced)).tracking(1.5).foregroundStyle(Art.ink3)
            SwiftUI.Text(Self.titled(title, italic)).font(.system(size: size, design: .serif)).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                SwiftUI.Text(detail).font(.system(size: 14)).foregroundStyle(Art.ink2).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 640, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    static func titled(_ plain: String, _ italic: String) -> AttributedString {
        var it = AttributedString(italic)
        it.inlinePresentationIntent = .emphasized
        return plain.isEmpty ? it : AttributedString(plain + " ") + it
    }
}

extension View {
    /// Dylan's other windows in the same family: warm background and teal controls.
    func artWindow() -> some View { background(Art.content.ignoresSafeArea()).tint(Art.accent) }
}

extension Art {
    /// The window around an `artWindow()` view: a title bar in the page colour instead of the grey default.
    static func style(_ w: NSWindow) {
        w.titlebarAppearsTransparent = true
        w.backgroundColor = contentNS
    }
}

/// D50 groups: white cards (radius 16) on the warm page, rows of about 52 pt split by 0.5 pt lines at 7 %.
/// The native grouped Form always tints its cards grey, so Settings lays sections out itself (macOS 15
/// `ForEach(sections:)`); the row styles below give controls the label-left, control-right form layout.
struct ArtFormStyle: FormStyle {
    func makeBody(configuration: Configuration) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(sections: configuration.content) { section in
                    if !section.header.isEmpty {
                        VStack(alignment: .leading) { section.header }
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Art.ink2)
                            .padding(.horizontal, 4).padding(.top, 6)
                    }
                    if !section.content.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(subviews: section.content) { row in
                                row.frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                                    .padding(.horizontal, 18).padding(.vertical, 9)
                                    .overlay(alignment: .top) {
                                        if row.id != section.content.first?.id { Rectangle().fill(Art.line).frame(height: 0.5).padding(.leading, 18) }
                                    }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Art.card))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Art.line, lineWidth: 0.5))
                        .shadow(color: Color(nsColor: Art.dynamic(Art.hex(0x3C2814, 0.04), .black.withAlphaComponent(0.2))), radius: 1, y: 1)
                    }
                    if !section.footer.isEmpty {
                        VStack(alignment: .leading) { section.footer }.font(.caption).foregroundStyle(Art.ink2).padding(.horizontal, 4)
                    }
                }
            }
            .padding(.horizontal, 30).padding(.top, 14).padding(.bottom, 30)
        }
        .labeledContentStyle(ArtRowStyle())
        .toggleStyle(ArtSwitchStyle())
    }
}

/// Label on the left, value or control on the right (also used by Picker and Stepper).
struct ArtRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 16) {
            configuration.label
            Spacer(minLength: 0)
            // Controls keep their natural width at the right (D50), unless that does not fit.
            ViewThatFits(in: .horizontal) {
                configuration.content.fixedSize()
                configuration.content
            }
            .foregroundStyle(Art.ink2)
        }
    }
}

/// A form row toggle: the label (and its hint) on the left, a teal switch on the right.
struct ArtSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) { configuration.label }
            Spacer(minLength: 0)
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch).labelsHidden()
        }
    }
}
