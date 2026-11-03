import DylanCore
import SwiftUI

/// Expanded → Dev (design D12): ports now; Docker, GitHub and script widgets join in later releases.
struct DevTab: View {
    @StateBox private var confirmKill: Int?
    private var ports: PortsProvider { PortsProvider.shared }
    private var model: AppModel { AppModel.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SwiftUI.Text(L("ports.title", ports.servers.count)).font(DY.font(11, .semibold)).foregroundStyle(DY.fg2)
                Spacer()
                SwiftUI.Text(L("ports.every")).font(DY.font(10.5)).foregroundStyle(DY.fg2)
            }
            if ports.servers.isEmpty {
                EmptyCard(symbol: "network", text: L("ports.empty"))
            }
            ForEach(ports.servers.prefix(6)) { s in
                HStack(spacing: 10) {
                    SwiftUI.Text(verbatim: ":" + String(s.listener.port))   // no digit grouping.font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                        .frame(width: 54, alignment: .leading)
                    SwiftUI.Text(s.listener.command).font(DY.mono).foregroundStyle(DY.fg2).frame(width: 60, alignment: .leading).lineLimit(1)
                    SwiftUI.Text(model.presentationMode ? "" : (s.project ?? "")).font(DY.font(12, .regular)).foregroundStyle(DY.fg).lineLimit(1)
                    Spacer()
                    NotchButton(title: L("button.open")) { ports.open(s) }
                    NotchButton(title: L("button.copy")) { ports.copy(s) }
                    NotchButton(title: confirmKill == s.id ? L("stats.confirmStop") : L("ports.kill"),
                                kind: confirmKill == s.id ? .destructive : .quiet) {
                        if confirmKill == s.id { ports.kill(s); confirmKill = nil } else { confirmKill = s.id }
                    }
                }
                .frame(height: 26)
            }
            Spacer(minLength: 0)
        }
        .onAppear { ports.scan() }
    }
}
