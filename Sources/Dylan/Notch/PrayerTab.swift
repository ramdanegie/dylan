import DylanCore
import SwiftUI

/// Expanded · Salat tab (D51): the next prayer with a running countdown, today's six times, Kemenag + Hijri date.
struct PrayerTab: View {
    private var p: PrayerProvider { PrayerProvider.shared }

    var body: some View {
        if let day = p.today, let next = p.next {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    SwiftUI.Text(p.city).font(DY.font(11, .semibold)).foregroundStyle(DY.fg2).lineLimit(1)
                    SwiftUI.Text(L("prayer.next")).font(DY.font(11, .regular)).foregroundStyle(DY.fg2).padding(.top, 6)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        SwiftUI.Text(p.name(next.prayer, on: next.at)).font(.system(size: 26, weight: .semibold, design: .serif)).foregroundStyle(.white)
                        SwiftUI.Text(time(next.at)).font(DY.font(15, .medium)).monospacedDigit().foregroundStyle(DY.fg)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        SwiftUI.Text(L("prayer.in", DurationFormat.running(max(0, next.at.timeIntervalSince(ctx.date)))))
                            .font(DY.font(12.5, .medium)).monospacedDigit().foregroundStyle(Color(nsColor: Art.hex(0x66D4CF)))
                    }
                    if p.adhanPlaying {
                        NotchButton(title: L("prayer.stopAdhan")) { AppModel.shared.perform(.stopAdhan) }.padding(.top, 6)
                    }
                }
                .frame(width: 190, alignment: .leading)
                VStack(spacing: 0) {
                    ForEach(PrayerTimes.Prayer.allCases, id: \.self) { pr in
                        let at = day.time(pr), isNext = pr == next.prayer && Calendar.current.isDate(at, inSameDayAs: next.at)
                        HStack {
                            SwiftUI.Text(p.name(pr)).font(DY.font(12.5, isNext ? .semibold : .regular))
                            Spacer()
                            SwiftUI.Text(time(at)).font(DY.font(12.5, isNext ? .semibold : .regular)).monospacedDigit()
                        }
                        .foregroundStyle(isNext ? .white : (at < Date() ? DY.fg2 : DY.fg))
                        .padding(.horizontal, 10).frame(height: 25)
                        .background(RoundedRectangle(cornerRadius: 7).fill(isNext ? Color.white.opacity(0.12) : .clear))
                    }
                    SwiftUI.Text(L("prayer.source", Date().formatted(.dateTime.weekday(.wide).day().month(.abbreviated).year().locale(L10n.locale)))
                                 + (p.showHijri ? "\n" + p.hijriToday : ""))
                        .font(DY.font(10.5, .regular)).foregroundStyle(DY.fg2).multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 6)
                }
            }
        } else {
            VStack(spacing: 10) {
                EmptyCard(symbol: "moon.stars", text: p.lookupFailed ? L("prayer.cityNotFound", p.city) : L("prayer.pickCity"))
                NotchButton(title: L("prayer.openSettings")) { SettingsWindow.show(section: .prayer) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func time(_ d: Date) -> String { PrayerProvider.clock(d) }
}

/// Expanded · Notifications tab (D57): today's history grouped per conversation; a click opens the app.
struct NotificationsTab: View {
    private var h: NotificationLog { NotificationLog.shared }
    private var model: AppModel { AppModel.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SwiftUI.Text(h.focusName.map { L("notifications.focusHeld", $0, h.history.heldCount) } ?? L("notifications.today"))
                    .font(DY.font(11, .semibold)).foregroundStyle(DY.fg2)
                Spacer()
                if !h.history.entries.isEmpty {
                    Button(L("button.clear")) { h.clear() }.buttonStyle(.plain).font(DY.font(11)).foregroundStyle(DY.fg2)
                }
            }
            if h.history.entries.isEmpty {
                EmptyCard(symbol: "bell", text: L("notifications.historyEmpty"))
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(h.history.groups) { g in
                        Button { h.open(g.latest) } label: { row(g) }.buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .onAppear { h.prune() }
    }

    private func row(_ g: NotificationHistory.Group) -> some View {
        let e = g.latest
        return HStack(alignment: .top, spacing: 10) {
            AppIcon(bundleID: e.bundleID).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    SwiftUI.Text(model.presentationMode ? e.app : e.title).font(DY.font(12.5, .semibold)).foregroundStyle(.white).lineLimit(1)
                    SwiftUI.Text("· " + e.app).font(DY.font(11, .regular)).foregroundStyle(DY.fg2).lineLimit(1)
                }
                if !model.presentationMode {
                    SwiftUI.Text(e.body).font(DY.font(11.5, .regular)).foregroundStyle(DY.fg).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                SwiftUI.Text(e.at.formatted(.dateTime.hour().minute().locale(L10n.locale))).font(DY.font(10.5)).monospacedDigit().foregroundStyle(DY.fg2)
                if g.count > 1 {
                    SwiftUI.Text("\(g.count)").font(DY.font(10, .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 5).frame(minWidth: 16, minHeight: 16).background(Capsule().fill(DY.fg))
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

struct AppIcon: View {
    var bundleID: String?
    var body: some View {
        if let id = bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            Image(systemName: "app.badge").foregroundStyle(DY.fg2)
        }
    }
}
