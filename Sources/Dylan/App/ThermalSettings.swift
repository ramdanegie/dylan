import AppKit
import DylanCore
import SMCKit
import SwiftUI

/// Settings → Suhu & Kipas (design D48): mode per fan, sensors, the curve, safety and display.
struct ThermalSettings: View {
    private var p: FanProvider { FanProvider.shared }
    private var d: UserDefaults { AppModel.store }
    @StateBox private var refresh = 0

    private func bool(_ key: String, _ def: Bool) -> Binding<Bool> {
        Binding(get: { _ = refresh; return d.object(forKey: key) as? Bool ?? def },
                set: { d.set($0, forKey: key); refresh += 1; FanProvider.shared.refreshSchedule(); AppModel.shared.fanChanged() })
    }

    var body: some View {
        FeatureToggles(features: [.thermal])
        Section {
            LabeledContent(L("fan.helper")) {
                HStack {
                    SwiftUI.Text(helperText).foregroundStyle(p.helperStatus == .enabled ? .green : .secondary)
                    if p.canControl {
                        if p.helperStatus == .enabled {
                            Button(L("fan.removeHelper")) { FanProvider.shared.removeHelper() }
                        } else {
                            Button(L("fan.installHelper")) { FanProvider.shared.installHelper() }
                        }
                    }
                }
            }
            SwiftUI.Text(L("fan.summary", p.fans.count, p.sensorCount)).foregroundStyle(.secondary)
            if p.hasFans && !FanProvider.signedByTeam { SwiftUI.Text(L("fan.adHoc")).font(.caption).foregroundStyle(.orange) }
            if p.externallyControlled { SwiftUI.Text(L("fan.external")).font(.caption).foregroundStyle(.orange) }
            if let e = p.lastError { SwiftUI.Text(e).font(.caption).foregroundStyle(.red) }
        }
        if p.hasFans {
            Section(L("fan.fans")) { ForEach(p.fans, id: \.index) { fanRow($0) } }
        }
        Section(L("fan.sensors")) {
            ForEach(ThermalSensors.Group.allCases, id: \.self) { g in
                LabeledContent(L("fan.sensor.\(g.rawValue)")) {
                    HStack {
                        SwiftUI.Text(p.format(p.temps[g])).monospacedDigit()
                        if p.hasFans {
                            Button(p.sensor == g ? L("fan.curveSensor") : L("fan.useSensor")) { _ = refresh; FanProvider.shared.sensor = g; refresh += 1 }
                                .buttonStyle(.link).disabled(p.sensor == g)
                        }
                    }
                }
            }
        }
        if p.hasFans { curveSection }
        Section(L("fan.safety")) {
            LabeledContent(L("fan.autoOnQuit")) { SwiftUI.Text(L("fan.always")).foregroundStyle(.secondary) }
            Toggle(L("fan.autoReturn"), isOn: bool("fan.autoReturn", false))
            Picker(L("fan.warn"), selection: Binding(get: { _ = refresh; return p.warnOn ? Int(p.warnAt) : 0 },
                                                      set: { v in
                                                          d.set(v > 0, forKey: "fan.warnOn")
                                                          if v > 0 { d.set(Double(v), forKey: "fan.warnAt") }
                                                          refresh += 1; FanProvider.shared.refreshSchedule()
                                                      })) {
                SwiftUI.Text(L("fan.warnOff")).tag(0)
                ForEach([85, 90, 95, 100], id: \.self) { SwiftUI.Text("≥ \($0)°C").tag($0) }
            }
            Toggle(L("fan.notchInfo"), isOn: Binding(get: { _ = refresh; return p.notchInfo },
                                                     set: { d.set($0, forKey: "fan.notchInfo"); refresh += 1; FanProvider.shared.postManual() }))
            Toggle(L("fan.menuTemp"), isOn: bool("fan.menuTemp", false))
            Picker(L("fan.unit"), selection: bool("fan.fahrenheit", false)) {
                SwiftUI.Text("°C").tag(false)
                SwiftUI.Text("°F").tag(true)
            }
            .pickerStyle(.segmented)
        }
    }

    private var helperText: String {
        guard p.hasFans else { return L("fan.noFans") }
        switch p.helperStatus {
        case .enabled: return L("fan.helperOn")
        case .requiresApproval: return L("fan.helperApproval")
        default: return L("fan.helperOff")
        }
    }

    private func fanRow(_ f: SMC.Fan) -> some View {
        _ = refresh
        let mode: FanMode? = p.preset == .curve ? p.modes[f.index] : p.preset == .auto ? .auto : nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                SpinningFan(rpm: f.rpm, color: .primary).frame(width: 16, height: 16)
                SwiftUI.Text(FanProvider.fanName(f.index, of: p.fans.count))
                SwiftUI.Text(FanProvider.rpm(f.rpm)).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: Binding(get: { mode ?? .curve }, set: { FanProvider.shared.setMode($0, fan: f.index); refresh += 1 })) {
                    ForEach(FanMode.allCases, id: \.self) { SwiftUI.Text(L("fan.mode.\($0.rawValue)")).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 260).disabled(!p.canControl)
            }
            switch mode {
            case .auto: SwiftUI.Text(L("fan.autoNote")).font(.caption).foregroundStyle(.secondary)
            case .curve: SwiftUI.Text(L("fan.curveNote", L("fan.sensor.\(p.sensor.rawValue)"))).font(.caption).foregroundStyle(.secondary)
            case .fixed:
                HStack {
                    SwiftUI.Text("\(Int(f.min))").font(.caption).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { _ = refresh; return p.fixed[f.index] },
                                          set: { v in var all = FanProvider.shared.fixed; all[f.index] = v; FanProvider.shared.fixed = all; refresh += 1 }),
                           in: f.min...f.max, step: 100)
                    SwiftUI.Text("\(Int(f.max))").font(.caption).foregroundStyle(.secondary)
                    SwiftUI.Text(FanProvider.rpm(p.fixed[f.index])).monospacedDigit().frame(width: 80, alignment: .trailing)
                }
            case nil: SwiftUI.Text(L("fan.presetNote", L("fan.preset.\(p.preset.rawValue)"))).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var curveSection: some View {
        _ = refresh
        let c = p.curve, now = p.temps[p.sensor] ?? p.cpu ?? 0
        return Section(L("fan.curveTitle", L("fan.sensor.\(p.sensor.rawValue)"), Int(now), Int(c.percent(at: now)))) {
            CurveChart(curve: c, now: now).frame(height: 140)
            ForEach(0..<4, id: \.self) { i in
                HStack {
                    SwiftUI.Text("\(Int(FanCurve.temps[i]))°C").monospacedDigit().frame(width: 44, alignment: .leading)
                    Slider(value: Binding(get: { c.percents[i] }, set: { v in
                        var n = FanProvider.shared.curve; n.set(i, v.rounded()); FanProvider.shared.curve = n; refresh += 1
                    }), in: 0...100)
                    SwiftUI.Text("\(Int(c.percents[i]))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
            }
            HStack {
                Picker(L("fan.response"), selection: bool("fan.smooth", true)) {
                    SwiftUI.Text(L("fan.fast")).tag(false)
                    SwiftUI.Text(L("fan.smooth")).tag(true)
                }
                .pickerStyle(.segmented)
                Button(L("fan.resetCurve")) { FanProvider.shared.curve = .standard; refresh += 1 }
            }
        }
    }
}

/// The curve over 30–100 °C with the current point (D48).
private struct CurveChart: View {
    var curve: FanCurve
    var now: Double

    var body: some View {
        GeometryReader { g in
            let x = { (t: Double) in g.size.width * (t - 30) / 70 }
            let y = { (p: Double) in g.size.height * (1 - p / 100) }
            let pts = [30.0, 40, 60, 75, 90, 100].map { CGPoint(x: x($0), y: y(curve.percent(at: $0))) }
            ZStack {
                Path { p in p.addLines(pts); p.addLine(to: CGPoint(x: g.size.width, y: g.size.height)); p.addLine(to: CGPoint(x: 0, y: g.size.height)) }
                    .fill(Color.accentColor.opacity(0.12))
                Path { p in p.addLines(pts) }.stroke(Color.accentColor, lineWidth: 2)
                ForEach(0..<4, id: \.self) { i in
                    Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                        .position(x: x(FanCurve.temps[i]), y: y(curve.percents[i]))
                }
                Circle().stroke(Color.primary, lineWidth: 2).frame(width: 10, height: 10)
                    .position(x: x(min(100, max(30, now))), y: y(curve.percent(at: now)))
            }
        }
        .accessibilityLabel(L("fan.curveA11y", Int(curve.percents[0]), Int(curve.percents[3])))
    }
}

/// D49: why Dylan needs a helper, before macOS asks for the admin password.
enum HelperSheetWindow {
    private static var window: NSWindow?

    static func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 440, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L("fan.sheetTitle")
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: HelperSheet { close() }.artWindow())
        Art.style(w)
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    static func close() { window?.close(); window = nil }
}

private struct HelperSheet: View {
    var done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SpinningFan(rpm: 2400, color: .primary).frame(width: 30, height: 30)
                VStack(alignment: .leading) {
                    SwiftUI.Text(L("fan.sheetTitle")).font(.headline)
                    SwiftUI.Text(L("fan.sheetSub")).foregroundStyle(.secondary)
                }
            }
            ForEach(1...3, id: \.self) { i in
                HStack(alignment: .top, spacing: 10) {
                    SwiftUI.Text("\(i)").font(.caption.bold()).frame(width: 18, height: 18).background(Circle().fill(Color.secondary.opacity(0.2)))
                    SwiftUI.Text(L("fan.sheetPoint\(i)")).fixedSize(horizontal: false, vertical: true)
                }
            }
            SwiftUI.Text(L("fan.sheetWarning")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !FanProvider.signedByTeam {
                SwiftUI.Text(L("fan.adHoc")).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                SwiftUI.Text(L("fan.sheetRemoveLater")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("fan.monitorOnly")) { done() }.keyboardShortcut(.cancelAction)
                Button(L("fan.installHelper")) { FanProvider.shared.installHelper(); done() }
                    .keyboardShortcut(.defaultAction).disabled(!FanProvider.signedByTeam)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
