import DylanCore
import SwiftUI

/// Expanded → Stats (design D13): six tiles and the top processes. Process alert & Stop are [Dev].
struct StatsTab: View {
    private var s: StatsProvider { StatsProvider.shared }
    private var model: AppModel { AppModel.shared }
    @StateBox private var confirmStop: Int32?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                tile(L("stats.cpu"), "\(Int(s.cpu * 100))%", spark: s.cpuHistory)
                tile("GPU", s.gpu.map { "\(Int($0 * 100))%" } ?? "—")
                tile(L("stats.memory"), "\(gb(s.memUsed)) / \(gb(s.memTotal)) GB")
                tile(L("stats.network"), "↓ \(Stats.formatRate(s.netDown, locale: L10n.locale))  ↑ \(Stats.formatRate(s.netUp, locale: L10n.locale))")
                tile("Disk", "\(gb(UInt64(max(0, s.diskUsed)))) / \(gb(UInt64(max(0, s.diskTotal)))) GB")
                tile(L("stats.battery"), model.battery.map { "\($0.percent)%" } ?? "—",
                     sub: model.battery.flatMap { b in b.isCharging ? (b.minutesToFull.map { L("stats.chargingFull", DurationFormat.long(TimeInterval($0 * 60), language: L10n.language)) } ?? L("stats.charging")) : nil })
            }
            HStack {
                SwiftUI.Text(L("stats.top")).font(DY.font(11, .semibold)).foregroundStyle(DY.fg2)
                Spacer()
                SwiftUI.Text("CPU").font(DY.font(10.5)).foregroundStyle(DY.fg2).frame(width: 54, alignment: .trailing)
                SwiftUI.Text(L("stats.memory")).font(DY.font(10.5)).foregroundStyle(DY.fg2).frame(width: 64, alignment: .trailing)
                Spacer().frame(width: 74)
            }
            ForEach(s.topProcesses, id: \.pid) { p in
                HStack(spacing: 8) {
                    SwiftUI.Text(model.presentationMode ? L("stats.process") : p.name).font(DY.font(12, .regular)).foregroundStyle(DY.fg).lineLimit(1)
                    Spacer()
                    ValueText(text: "\(Int(p.cpu))%", color: p.cpu >= 150 ? DY.action : DY.fg).frame(width: 54, alignment: .trailing)
                    ValueText(text: mem(p.rssKB), color: DY.fg2).frame(width: 64, alignment: .trailing)
                    Group {
                        if model.isDeveloper && s.isHot(p.pid) {
                            NotchButton(title: confirmStop == p.pid ? L("stats.confirmStop") : L("stats.stop"),
                                        kind: confirmStop == p.pid ? .destructive : .quiet) {
                                if confirmStop == p.pid { StatsProvider.shared.stop(p.pid); confirmStop = nil } else { confirmStop = p.pid }
                            }
                        }
                    }
                    .frame(width: 74, alignment: .trailing)
                }
                .frame(height: 22)
            }
        }
        .onAppear { StatsProvider.shared.refreshSchedule() }
        .onDisappear { DispatchQueue.main.async { StatsProvider.shared.refreshSchedule() } }
    }

    private func gb(_ b: UInt64) -> String { String(format: "%.1f", Double(b) / 1_073_741_824).replacingOccurrences(of: ".", with: L10n.language == "id" ? "," : ".") }
    private func mem(_ kb: Int) -> String { kb >= 1_048_576 ? "\(gb(UInt64(kb) * 1024)) GB" : "\(kb / 1024) MB" }

    private func tile(_ title: String, _ value: String, sub: String? = nil, spark: [Double] = []) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SwiftUI.Text(title).font(DY.font(10.5, .semibold)).foregroundStyle(DY.fg2)
            ValueText(text: value).font(.system(size: 14, weight: .semibold))
            if let sub { SwiftUI.Text(sub).font(DY.font(10.5, .regular)).foregroundStyle(DY.fg2).lineLimit(1) }
            if !spark.isEmpty { Sparkline(values: spark).frame(height: 16) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}

struct Sparkline: View {
    var values: [Double]
    var body: some View {
        GeometryReader { g in
            Path { p in
                guard values.count > 1 else { return }
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: g.size.width * CGFloat(i) / CGFloat(values.count - 1), y: g.size.height * (1 - CGFloat(min(1, max(0, v)))))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
            }
            .stroke(DY.fg, lineWidth: 1.2)
        }
        .accessibilityHidden(true)
    }
}
