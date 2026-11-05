import AppKit
import DylanCore
import SwiftUI

// Per-item animations (FR-108, design D54). Each has its own switch in Settings → Animations, and Reduce Motion
// turns all of them off.

/// One lap of light around the island's edge when a notification arrives (1.2 s), in the app's colour.
struct GlowRing: View {
    var token: Int
    var color: Color
    var radius: CGFloat
    var hasNotch: Bool
    @StateBox private var angle: Double = 0
    @StateBox private var visible = false

    var body: some View {
        let gradient = AngularGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.62),
                                               .init(color: color.opacity(0.4), location: 0.74), .init(color: color, location: 0.84),
                                               .init(color: .white, location: 0.88), .init(color: .clear, location: 0.93)],
                                       center: .center, angle: .degrees(angle))
        Group {
            if hasNotch { NotchShape(bottomRadius: radius).stroke(gradient, lineWidth: 2) }
            else { PillShape(radius: radius).stroke(gradient, lineWidth: 2) }
        }
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(false)
        .onChange(of: token) {
            guard Prefs.shared.glowLine, Prefs.motionAllowed else { return }
            angle = 0; visible = true
            withAnimation(.linear(duration: 1.2)) { angle = 360 }
            withAnimation(.easeOut(duration: 0.25).delay(1.1)) { visible = false }
        }
    }
}

/// A 2 pt line along the island's lower edge: what is left of the Pomodoro, timer or prayer countdown (D54).
struct TimeLine: View {
    var radius: CGFloat
    private var model: AppModel { AppModel.shared }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            if let f = fraction(ctx.date) {
                GeometryReader { g in
                    let inset = radius + 2, w = max(0, g.size.width - 2 * inset)
                    Capsule().fill(Color(nsColor: Art.hex(0x66D4CF)))
                        .frame(width: w * f, height: 2)
                        .position(x: inset + w * f / 2, y: g.size.height - 1)
                        .animation(.linear(duration: 1), value: f)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Remaining share of the running countdown, nil when there is none.
    private func fraction(_ now: Date) -> Double? {
        if let t = model.timer, !t.isPaused { return t.remaining(now: now) / max(1, t.duration) }
        if let a = model.center.activities["prayer"], let p = a.progress { return 1 - p }
        return nil
    }
}

/// The next notification peeking as a layer under Peek (D54): a narrower sheet with "+N".
struct StackLayer: View {
    var count: Int
    var width: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.09))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            .overlay(alignment: .bottom) {
                SwiftUI.Text("+\(count)").font(DY.font(10, .semibold)).foregroundStyle(DY.fg2).padding(.bottom, 2)
            }
            .frame(width: width - 28, height: 22)
            .allowsHitTesting(false)
            .accessibilityLabel(L("notifications.more", count))
    }
}

/// Small confetti from the island when every task of the day is ticked (D54), once a day.
struct Confetti: View {
    var token: Int
    @StateBox private var t: CGFloat = 1
    private static let colors: [UInt32] = [0xFF453A, 0xFFD60A, 0x30D158, 0x0A84FF, 0xBF5AF2, 0x66D4CF, 0xFF9F0A]

    var body: some View {
        ZStack {
            ForEach(0..<18, id: \.self) { i in
                let a = Double(i) / 18 * .pi - .pi, r = 60 + Double((i * 37) % 50)
                RoundedRectangle(cornerRadius: 1).fill(Color(nsColor: Art.hex(Self.colors[i % Self.colors.count])))
                    .frame(width: 5, height: 8)
                    .rotationEffect(.degrees(Double(i * 47 % 360) * Double(t)))
                    .offset(x: cos(a) * r * 1.6 * t, y: (-sin(a) * r * 0.5 + 50) * t)
                    .opacity(t < 1 ? 1 - Double(t) * 0.8 : 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: token) {
            guard Prefs.shared.confetti, Prefs.motionAllowed else { return }
            t = 0
            withAnimation(.timingCurve(0.2, 0.7, 0.3, 1, duration: 2.4)) { t = 1 }
        }
    }
}
