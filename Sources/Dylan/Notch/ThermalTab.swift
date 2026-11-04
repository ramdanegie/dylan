import DylanCore
import SMCKit
import SwiftUI

/// Expanded → Suhu (design D45): CPU with history, GPU/SSD/battery, each fan, and the presets.
struct ThermalTab: View {
    private var p: FanProvider { FanProvider.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SwiftUI.Text(p.modelName).font(DY.font(11, .semibold)).foregroundStyle(DY.fg2).lineLimit(1)
            HStack(spacing: 8) {
                cpuCard
                VStack(spacing: 6) {
                    small("GPU", p.temps[.gpu])
                    small("SSD", p.temps[.ssd])
                    small(L("stats.battery"), p.temps[.battery])
                }
                .frame(width: 140)
            }
            if p.hasFans {
                HStack(spacing: 8) { ForEach(p.fans, id: \.index) { fanCard($0) } }
                if p.externallyControlled {
                    SwiftUI.Text(L("fan.external")).font(DY.font(10.5)).foregroundStyle(DY.action).lineLimit(2)
                }
                HStack(spacing: 4) { ForEach(FanPreset.allCases, id: \.self) { presetButton($0) } }
            } else {
                // D49: Mac without fans.
                SwiftUI.Text(p.throttling ? L("fan.throttling") : L("fan.noFans")).font(DY.font(11)).foregroundStyle(p.throttling ? DY.action : DY.fg2)
            }
        }
        .onAppear { FanProvider.shared.tabOpen = true; FanProvider.shared.sample() }
        .onDisappear { DispatchQueue.main.async { FanProvider.shared.tabOpen = false } }
    }

    private var cpuCard: some View {
        let c = p.cpu ?? 0
        let heat = FanMath.heat(c)
        let tone: Color = heat == .hot ? DY.fail : heat == .warm ? .orange : DY.ok
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                SwiftUI.Text("CPU").font(DY.font(10.5, .semibold)).foregroundStyle(DY.fg2)
                SwiftUI.Text(L("fan.heat.\(heat)")).font(DY.font(10.5, .semibold)).foregroundStyle(tone)
            }
            SwiftUI.Text(p.format(p.cpu)).font(.system(size: 30, weight: .semibold)).monospacedDigit()
                .foregroundStyle(DY.fg).contentTransition(.numericText())
            // 30–100 °C mapped onto the sparkline's 0–1.
            Sparkline(values: p.cpuHistory.map { ($0 - 30) / 70 }).frame(height: 22)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }

    private func small(_ title: String, _ v: Double?) -> some View {
        HStack {
            SwiftUI.Text(title).font(DY.font(10.5, .semibold)).foregroundStyle(DY.fg2)
            Spacer()
            ValueText(text: p.format(v))
        }
        .padding(.horizontal, 10).frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func fanCard(_ f: SMC.Fan) -> some View {
        HStack(spacing: 8) {
            SpinningFan(rpm: f.rpm).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                SwiftUI.Text(FanProvider.fanName(f.index, of: p.fans.count)).font(DY.font(11, .semibold)).foregroundStyle(DY.fg)
                SwiftUI.Text("\(Int(f.min).formatted())–\(Int(f.max).formatted())").font(DY.font(10)).foregroundStyle(DY.fg2)
            }
            Spacer()
            SwiftUI.Text(FanProvider.rpm(f.rpm)).font(DY.font(12, .semibold)).monospacedDigit().foregroundStyle(DY.fg)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }

    private func presetButton(_ preset: FanPreset) -> some View {
        let on = p.preset == preset
        return Button { FanProvider.shared.setPreset(preset) } label: {
            VStack(spacing: 1) {
                SwiftUI.Text(L("fan.preset.\(preset.rawValue)")).font(DY.font(11, .semibold)).lineLimit(1)
                SwiftUI.Text(L("fan.hint.\(preset.rawValue)")).font(DY.font(9.5)).opacity(0.6).lineLimit(1)
            }
            .foregroundStyle(on ? Color.black : DY.fg)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Color.white : Color.white.opacity(0.06)))
        }
        .buttonStyle(PressScale())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Fan glyph that turns with the RPM (design: one turn per 2600/rpm s), still under Reduce Motion.
struct SpinningFan: View {
    var rpm: Double
    var color: Color = DY.fg
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion || rpm < 1 {
            glyph(0)
        } else {
            TimelineView(.animation) { t in
                let period = max(0.18, 2600 / max(rpm, 400))
                glyph(t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period * 360)
            }
        }
    }

    private func glyph(_ deg: Double) -> some View {
        Image(systemName: "fan.fill").resizable().scaledToFit().foregroundStyle(color).rotationEffect(.degrees(deg))
            .accessibilityHidden(true)
    }
}
