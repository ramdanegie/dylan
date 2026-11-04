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
                    // verbatim + String(): no digit grouping (":3000", not ":3,000").
                    SwiftUI.Text(verbatim: ":" + String(s.listener.port))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
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
            DockerSection()
            GitHubSection()
            WidgetSection()
            Spacer(minLength: 0)
        }
        .onAppear { ports.scan(); DevIntegrations.shared.devTabVisible(true) }
        .onDisappear { DevIntegrations.shared.devTabVisible(false) }
    }
}

private struct SectionHeader: View {
    var title: String
    var trailing: String?
    var body: some View {
        HStack {
            SwiftUI.Text(title).font(DY.font(11, .semibold)).foregroundStyle(DY.fg2)
            Spacer()
            if let trailing { SwiftUI.Text(trailing).font(DY.font(10.5)).foregroundStyle(DY.fg2) }
        }
        .padding(.top, 4)
    }
}

struct DockerSection: View {
    private var d: DevIntegrations { DevIntegrations.shared }
    private var model: AppModel { AppModel.shared }
    var body: some View {
        if model.features.isEnabled(.docker), d.dockerAvailable, !d.containers.isEmpty {
            SectionHeader(title: "Docker · \(d.containers.count)", trailing: nil)
            ForEach(d.containers.prefix(3)) { c in
                HStack(spacing: 8) {
                    Circle().fill(c.running ? DY.ok : DY.fg2).frame(width: 6, height: 6)
                    SwiftUI.Text(model.presentationMode ? "" : c.name).font(DY.font(12, .regular)).foregroundStyle(DY.fg).lineLimit(1)
                    SwiftUI.Text(c.status).font(DY.font(10.5)).foregroundStyle(DY.fg2).lineLimit(1)
                    Spacer()
                    NotchButton(title: c.running ? L("docker.restart") : L("docker.start")) { d.docker(c.running ? "restart" : "start", c) }
                    if c.running { NotchButton(title: L("docker.stop"), kind: .quiet) { d.docker("stop", c) } }
                    NotchButton(title: L("docker.logs")) { d.dockerLogs(c) }
                }
                .frame(height: 24)
            }
        }
    }
}

struct GitHubSection: View {
    private var d: DevIntegrations { DevIntegrations.shared }
    private var model: AppModel { AppModel.shared }
    var body: some View {
        if model.features.isEnabled(.github) {
            SectionHeader(title: L("ci.title"), trailing: d.reviewRequests.map { L("ci.reviews", $0) })
            if d.runs.isEmpty {
                SwiftUI.Text(L("ci.empty")).font(DY.font(11, .regular)).foregroundStyle(DY.fg2)
            }
            ForEach(Array(d.runs.prefix(3).enumerated()), id: \.offset) { _, item in
                HStack(spacing: 8) {
                    Group {
                        switch item.run.state {
                        case .running: Spinner()
                        case .success: Image(systemName: "checkmark").foregroundStyle(DY.ok)
                        case .failure: Image(systemName: "xmark").foregroundStyle(DY.fail)
                        case .other: Image(systemName: "minus").foregroundStyle(DY.fg2)
                        }
                    }
                    .font(.system(size: 10, weight: .bold)).frame(width: 14)
                    if !model.presentationMode {
                        SwiftUI.Text(item.repo.split(separator: "/").last.map(String.init) ?? item.repo).font(DY.font(12, .regular)).foregroundStyle(DY.fg)
                        SwiftUI.Text(item.run.branch).font(DY.mono).foregroundStyle(DY.fg2).lineLimit(1)
                        SwiftUI.Text(item.run.name).font(DY.font(11, .regular)).foregroundStyle(DY.fg2).lineLimit(1)
                    }
                    Spacer()
                    if let u = URL(string: item.run.url) { NotchButton(title: L("button.open")) { model.perform(.openURL(u)) } }
                }
                .frame(height: 22)
            }
        }
    }
}

struct WidgetSection: View {
    private var d: DevIntegrations { DevIntegrations.shared }
    private var model: AppModel { AppModel.shared }
    var body: some View {
        // Widget titles and values are whatever the script prints: hidden while presenting.
        if model.features.isEnabled(.widgets), !model.presentationMode, !(d.widgets.isEmpty && d.widgetErrors.isEmpty) {
            SectionHeader(title: L("widgets.title"), trailing: "~/.config/dylan/widgets")
            HStack(spacing: 8) {
                ForEach(d.widgets.keys.sorted(), id: \.self) { k in
                    if let w = d.widgets[k] {
                        VStack(alignment: .leading, spacing: 2) {
                            SwiftUI.Text(w.title).font(DY.font(10.5, .semibold)).foregroundStyle(DY.fg2)
                            SwiftUI.Text(w.value).font(DY.font(13, .semibold))
                                .foregroundStyle(w.state == .error ? DY.fail : (w.state == .warn ? DY.action : .white))
                        }
                        .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                    }
                }
                ForEach(d.widgetErrors.keys.sorted(), id: \.self) { k in
                    SwiftUI.Text("\((k as NSString).lastPathComponent): \(d.widgetErrors[k] ?? "")").font(DY.font(10.5)).foregroundStyle(DY.fail)
                }
            }
        }
    }
}
