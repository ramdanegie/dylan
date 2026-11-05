import AppKit
import AVFoundation
import DylanCore
import SwiftUI
import Translation

/// Expanded panel with icon tabs around the notch (design "Tab bar Expanded"), D8, D9, D18, D23.
struct ExpandedView: View {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    @Namespace private var tabNS
    private var model: AppModel { AppModel.shared }

    var body: some View {
        VStack(spacing: 0) {
            tabBar.frame(height: max(notchHeight, 30))
            Group {
                if model.dropping { DropZonesView() } else {
                switch model.selectedTab {
                case .home: HomeTab()
                case .media: MediaTab()
                case .prayer: PrayerTab()
                case .notifications: NotificationsTab()
                case .clipboard: ClipboardTab()
                case .shelf: ShelfTab()
                case .discord: DiscordTab()
                case .stats: StatsTab()
                case .thermal: ThermalTab()
                case .dev: DevTab()
                case .terminal: TerminalTab()
                case .agents: AgentsTab()
                }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var tabBar: some View {
        let tabs = model.tabs
        // Design: Home · Media (· Discord · Shelf) left of the notch, Clipboard (· Stats) · Agents (· Dev) right.
        // Terminal goes left: the right side has no room for a fifth tab and its label.
        let leftTabs: [Tab] = [.home, .media, .prayer, .discord, .shelf, .terminal]
        let left = tabs.filter { leftTabs.contains($0) }
        let right = tabs.filter { !leftTabs.contains($0) }
        // The active tab shows its name only when that still fits beside the notch (many tabs in Developer Mode).
        let side = (([.media, .clipboard, .dev].contains(model.selectedTab) ? 720 : 640) - notchWidth) / 2 - 16
        func fits(_ list: [Tab], extra: CGFloat) -> Bool {
            guard list.contains(model.selectedTab) else { return true }
            return CGFloat(list.count - 1) * 30 + CGFloat(model.selectedTab.title.count) * 7.2 + 40 + extra <= side
        }
        let leftTitle = fits(left, extra: 0), rightTitle = fits(right, extra: 30 + 20)
        return HStack(spacing: 0) {
            HStack(spacing: 4) { ForEach(left) { tabButton($0, title: leftTitle) } }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16)
            Color.clear.frame(width: notchWidth)
            HStack(spacing: 4) {
                ForEach(right) { tabButton($0, title: rightTitle) }
                Button { SettingsWindow.show() } label: {
                    Image(systemName: "gearshape").font(.system(size: 12)).foregroundStyle(DY.fg2).frame(width: 26, height: 22)
                }
                .buttonStyle(PressScale()).accessibilityLabel(L("menu.settings"))
                StatusDots()
            }
            .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 16)
        }
    }

    private func tabButton(_ t: Tab, title: Bool) -> some View {
        let active = model.selectedTab == t, named = active && title
        return Button {
            withAnimation(DY.spring) { model.selectedTab = t }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: t.symbol).font(.system(size: 11, weight: .semibold))
                if named { SwiftUI.Text(t.title).font(DY.font(12, .semibold)).lineLimit(1).fixedSize() }
            }
            .foregroundStyle(active ? .white : DY.fg2)
            .padding(.horizontal, named ? 10 : 0)
            .frame(minWidth: 26, minHeight: 22)
            .background {
                if active { Capsule().fill(Color.white.opacity(0.14)).matchedGeometryEffect(id: "tab.pill", in: tabNS) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .help(t.title)
        .accessibilityLabel(t.title)
    }
}

// MARK: Home (D8 / D33)

struct HomeTab: View {
    private var model: AppModel { AppModel.shared }

    var body: some View {
        VStack(spacing: 12) {
            if model.mirrorOn { MirrorView().frame(maxHeight: .infinity) }
            else if model.scratchpadOpen, !model.presentationMode { ScratchpadView().frame(maxHeight: .infinity) }
            else { columns }
            if !Prefs.shared.modules.isEmpty, !model.mirrorOn, !model.scratchpadOpen { ModulesRow() }
            if model.features.isEnabled(.reminders) { QuickAddField() }
            if model.isDeveloper { RunningChips() }
            HStack(spacing: 6) {
                BatteryLine()
                UtilityButtons()
            }
        }
        .onDisappear { MirrorCamera.shared.stop() }
    }

    private var columns: some View {
            HStack(alignment: .top, spacing: 14) {
                NowPlayingCard().frame(maxWidth: .infinity, alignment: .leading)
                Divider().overlay(Color.white.opacity(0.08))
                AgendaCard().frame(maxWidth: .infinity, alignment: .leading)
                Divider().overlay(Color.white.opacity(0.08))
                VStack(spacing: 8) {
                    WeatherMini()
                    TimerCard()
                }
                .frame(width: 168)
            }
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct ScratchpadView: View {
    @StateBox private var text = Scratchpad.load()
    var body: some View {
        TextEditor(text: $text)
            .font(DY.font(12.5, .regular)).foregroundStyle(.white)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            .onChange(of: text) { Scratchpad.save(text) }
            .accessibilityLabel(L("scratchpad.title"))
    }
}

struct MirrorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: MirrorCamera.shared.session)
        layer.videoGravity = .resizeAspectFill
        layer.cornerRadius = 12
        layer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))   // mirror image
        v.layer = layer
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct NowPlayingCard: View {
    private var model: AppModel { AppModel.shared }

    var body: some View {
        if let m = model.media {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Artwork(image: m.artwork, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        SwiftUI.Text(m.title).font(DY.font(13, .semibold)).foregroundStyle(.white).lineLimit(1)
                        SwiftUI.Text("\(m.artist) · \(m.sourceName)")
                            .font(DY.font(11.5, .regular)).foregroundStyle(DY.fg2).lineLimit(1)
                    }
                }
                if m.duration > 0 {   // browser tabs have no known length (FR-11)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    VStack(spacing: 3) {
                        ProgressBar(progress: m.livePosition(ctx.date) / m.duration, color: model.mediaAccent)
                            .frame(height: 3)
                        HStack {
                            ValueText(text: DurationFormat.running(m.livePosition(ctx.date)), color: DY.fg2)
                            Spacer()
                            ValueText(text: DurationFormat.running(m.duration), color: DY.fg2)
                        }
                        .font(.system(size: 10))
                    }
                }
                }
                MediaButtons(size: 13).frame(maxWidth: .infinity)
            }
        } else {
            EmptyCard(symbol: "music.note", text: L("home.noMusic"))
        }
    }
}

struct AgendaCard: View {
    private var model: AppModel { AppModel.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SwiftUI.Text(L("home.today", Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(L10n.locale))))
                .font(DY.font(11, .semibold)).foregroundStyle(DY.fg2)
            if CalendarProvider.shared.status != .fullAccess {
                SwiftUI.Text(L("home.calendarOff")).font(DY.font(12, .regular)).foregroundStyle(DY.fg2)
                NotchButton(title: L("button.allowCalendar")) { CalendarProvider.shared.start(requestAccess: true) }
            } else if let next = model.nextMeetingToday {
                VStack(alignment: .leading, spacing: 2) {
                    SwiftUI.Text(model.presentationMode ? L("generic.meeting") : next.title)
                        .font(DY.font(13, .semibold)).foregroundStyle(.white).lineLimit(1)
                    SwiftUI.Text(timeRange(next) + (next.link.map { " · " + $0.service.rawValue.capitalized } ?? ""))
                        .font(DY.font(11.5, .regular)).foregroundStyle(DY.fg2)
                    HStack {
                        TimelineView(.periodic(from: .now, by: 30)) { ctx in
                            SwiftUI.Text(relative(next.start, ctx.date)).font(DY.font(11.5)).foregroundStyle(DY.info)
                        }
                        Spacer()
                        if let url = next.link?.appURL ?? next.link?.url {
                            NotchButton(title: L("button.join"), kind: .primaryNeutral) { model.perform(.join(url)) }
                        }
                    }
                }
                ForEach(model.meetings.filter { !$0.isAllDay && $0.start > next.start }.sorted { $0.start < $1.start }.prefix(2), id: \.id) { e in
                    HStack(spacing: 8) {
                        SwiftUI.Text(e.start.formatted(.dateTime.hour().minute().locale(L10n.locale))).font(DY.font(11.5)).monospacedDigit().foregroundStyle(DY.fg2)
                        SwiftUI.Text(model.presentationMode ? L("generic.meeting") : e.title).font(DY.font(11.5, .regular)).foregroundStyle(DY.fg).lineLimit(1)
                    }
                }
            } else {
                SwiftUI.Text(L("home.noMeetings")).font(DY.font(12, .regular)).foregroundStyle(DY.fg2)
            }
            // The Tasks module shows the same list; not twice.
            if model.features.isEnabled(.reminders), !Prefs.shared.modules.contains(.tasks) { RemindersList() }
        }
    }

    private func timeRange(_ e: MeetingSchedule.Event) -> String {
        let f = Date.FormatStyle.dateTime.hour().minute().locale(L10n.locale)
        return "\(e.start.formatted(f))–\(e.end.formatted(f))"
    }

    private func relative(_ start: Date, _ now: Date) -> String {
        let s = start.timeIntervalSince(now)
        if s <= 0 { return L("meeting.started") }
        return L("meeting.startsIn", DurationFormat.long(s, language: L10n.language))
    }
}

/// Today's reminders with checkboxes (design D33).
struct RemindersList: View {
    private var r: RemindersProvider { RemindersProvider.shared }
    private var model: AppModel { AppModel.shared }
    var body: some View {
        if r.status != .fullAccess {
            Button(L("reminders.allow")) { RemindersProvider.shared.start(requestAccess: true) }
                .buttonStyle(.plain).font(DY.font(11)).foregroundStyle(DY.info)
        } else if !r.items.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                SwiftUI.Text(L("reminders.today")).font(DY.font(10.5, .semibold)).foregroundStyle(DY.fg2).padding(.top, 4)
                ForEach(r.items.prefix(3)) { item in
                    HStack(spacing: 6) {
                        Button { RemindersProvider.shared.complete(item) } label: {
                            Image(systemName: "circle").font(.system(size: 11)).foregroundStyle(DY.fg2)
                        }
                        .buttonStyle(.plain).accessibilityLabel(L("reminders.complete"))
                        SwiftUI.Text(model.presentationMode ? L("reminders.generic") : item.title)
                            .font(DY.font(11.5, .regular)).foregroundStyle(DY.fg).lineLimit(1)
                        if item.overdue { SwiftUI.Text(L("reminders.overdue")).font(DY.font(10)).foregroundStyle(DY.action) }
                    }
                }
            }
        }
    }
}

struct WeatherMini: View {
    private var w: WeatherProvider { WeatherProvider.shared }
    private var model: AppModel { AppModel.shared }
    var body: some View {
        if model.features.isEnabled(.weather), let c = w.current {
            let d = Weather.describe(c.code)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Image(systemName: d.symbol).font(.system(size: 13)).symbolRenderingMode(.multicolor)
                    SwiftUI.Text("\(Int(c.temperature.rounded()))°").font(DY.font(15, .semibold)).foregroundStyle(.white)
                    SwiftUI.Text(w.place ?? model.weatherCity).font(DY.font(10.5)).foregroundStyle(DY.fg2).lineLimit(1)
                }
                SwiftUI.Text(L(d.key) + (c.low.flatMap { lo in c.high.map { " · \(Int(lo.rounded()))° / \(Int($0.rounded()))°" } } ?? ""))
                    .font(DY.font(10.5, .regular)).foregroundStyle(DY.fg2).lineLimit(1)
                if let rain = Weather.nextRain(c), rain > Date() {
                    SwiftUI.Text(L("weather.rainAt", rain.formatted(.dateTime.hour().minute().locale(L10n.locale))))
                        .font(DY.font(10.5)).foregroundStyle(DY.info)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// "+ Rapat tim besok 10.00" → preview → saved as event or reminder (FR-85).
struct QuickAddField: View {
    @StateBox private var text = ""
    @StateBox private var note: String?
    private var model: AppModel { AppModel.shared }
    var body: some View {
        let parsed = QuickAdd.parse(text, now: Date())
        HStack(spacing: 8) {
            Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(DY.fg2)
            TextField(L("quickAdd.placeholder"), text: $text)
                .textFieldStyle(.plain).font(DY.font(12, .regular)).foregroundStyle(.white)
                .onSubmit {
                    guard let p = QuickAdd.parse(text, now: Date()) else { return }
                    note = RemindersProvider.shared.save(p)
                    text = ""
                    RemindersProvider.shared.reload()
                }
            if let p = parsed, !text.isEmpty {
                SwiftUI.Text((p.kind == .event ? L("quickAdd.event") : L("quickAdd.reminder"))
                             + (p.date.map { " · " + $0.formatted(p.hasTime ? .dateTime.weekday(.abbreviated).hour().minute().locale(L10n.locale)
                                                                    : .dateTime.weekday(.abbreviated).day().locale(L10n.locale)) } ?? ""))
                    .font(DY.font(10.5)).foregroundStyle(DY.info).lineLimit(1)
            } else if let note {
                SwiftUI.Text(note).font(DY.font(10.5)).foregroundStyle(DY.fg2).lineLimit(1)
            }
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(Capsule().fill(DY.control))
    }
}

struct RunningChips: View {
    private var model: AppModel { AppModel.shared }
    var body: some View {
        let items = model.center.ordered.filter { [.agent, .command, .script].contains($0.kind) }
        if !items.isEmpty {
            HStack(spacing: 6) {
                ForEach(items.prefix(4)) { a in
                    HStack(spacing: 5) {
                        Glyph(activity: a)
                        if a.state == .running { Spinner() }
                        SwiftUI.Text(model.displayDetail(a)).font(DY.font(11.5, .regular)).foregroundStyle(DY.fg).lineLimit(1)
                    }
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(DY.control))
                }
                Spacer()
            }
        }
    }
}

/// Text buttons, not icons only, so they read clearly for everyone (design D33).
struct UtilityButtons: View {
    private var model: AppModel { AppModel.shared }
    var body: some View {
        HStack(spacing: 6) {
            if model.features.isEnabled(.colorPicker) {
                NotchButton(title: L("color.pick")) { model.pickColor() }
            }
            if model.features.isEnabled(.mirror) {
                NotchButton(title: model.mirrorOn ? L("mirror.stop") : L("mirror.button")) {
                    model.mirrorOn ? MirrorCamera.shared.stop() : MirrorCamera.shared.start()
                }
            }
            if model.features.isEnabled(.scratchpad) {
                NotchButton(title: model.scratchpadOpen ? L("button.done") : L("scratchpad.button")) { model.scratchpadOpen.toggle() }
            }
            Button { SettingsWindow.show(section: .utilities) } label: {
                Image(systemName: "square.grid.2x2").font(.system(size: 11)).foregroundStyle(DY.fg2).frame(width: 22, height: 22)
            }
            .buttonStyle(PressScale()).help(L("module.edit")).accessibilityLabel(L("module.edit"))
            if model.features.isEnabled(.keepAwake) {
                if let k = model.keepAwake {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        NotchButton(title: k.remaining(now: ctx.date).map { L("keepAwake.stopIn", DurationFormat.long($0, language: L10n.language)) }
                                    ?? L("keepAwake.stop")) { model.stopKeepAwake() }
                    }
                } else if DownloadsProvider.shared.active {
                    NotchButton(title: L("keepAwake.untilDownloads")) { model.startKeepAwake(minutes: 0); model.keepAwakeUntilDownloads = true }
                } else {
                    NotchButton(title: L("keepAwake.button")) { model.startKeepAwake() }
                }
            }
        }
    }
}

struct BatteryLine: View {
    private var model: AppModel { AppModel.shared }
    var body: some View {
        if let b = model.battery, model.features.isEnabled(.battery) {
            HStack(spacing: 6) {
                Image(systemName: b.onAC ? "bolt.fill" : "battery.75percent").font(.system(size: 11)).foregroundStyle(b.percent <= 20 && !b.onAC ? DY.action : DY.fg2)
                SwiftUI.Text(b.onAC && b.isCharging
                             ? (b.minutesToFull.map { L("battery.chargingFull", b.percent, DurationFormat.long(TimeInterval($0 * 60), language: L10n.language)) } ?? L("battery.charging", b.percent))
                             : "\(b.percent)%")
                    .font(DY.font(11, .regular)).foregroundStyle(DY.fg2).monospacedDigit()
                if b.lowPowerMode { SwiftUI.Text(L("battery.lowPower")).font(DY.font(11, .regular)).foregroundStyle(DY.action) }
                Spacer()
            }
        }
    }
}

// MARK: Media (D23, v1.0 subset)

struct MediaTab: View {
    private var model: AppModel { AppModel.shared }
    @StateBox private var scrub: Double?
    @StateBox private var showOutputs = false

    var body: some View {
        if let m = model.media {
            HStack(alignment: .top, spacing: 18) {
                Artwork(image: m.artwork, size: 150)
                    .shadow(color: model.mediaAccent.opacity(0.45), radius: 24)
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        SwiftUI.Text(m.sourceName).font(DY.font(11, .semibold)).foregroundStyle(DY.fg2)
                        SwiftUI.Text(m.title).font(DY.font(17, .semibold)).foregroundStyle(.white).lineLimit(1)
                        SwiftUI.Text("\(m.artist) · \(m.album)").font(DY.font(12.5, .regular)).foregroundStyle(DY.fg2).lineLimit(1)
                        if m.source == .spotify, let n = SpotifyAccount.shared.next {
                            SwiftUI.Text(L("spotify.next", [n.name, n.detail].compactMap { $0 }.joined(separator: " — ")))
                                .font(DY.font(11, .regular)).foregroundStyle(DY.fg2).lineLimit(1)
                        }
                    }
                    // A browser tab has no known length: no timeline (FR-11).
                    if m.duration > 0 {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let pos = scrub ?? m.livePosition(ctx.date)
                        VStack(spacing: 4) {
                            ScrubBar(fraction: pos / m.duration, color: model.mediaAccent,
                                     label: L("media.position")) { f, done in
                                scrub = f * m.duration
                                if done, m.hasFullControls { MediaProvider.shared.seek(to: f * m.duration) }
                                if done { scrub = nil }
                            }
                            HStack {
                                ValueText(text: DurationFormat.running(pos), color: DY.fg2)
                                Spacer()
                                ValueText(text: DurationFormat.running(m.duration), color: DY.fg2)
                            }
                        }
                    }
                    }
                    HStack(spacing: 18) {
                        if m.hasFullControls { toggle("shuffle", on: m.shuffle, label: L("media.shuffle")) { MediaProvider.shared.toggleShuffle() } }
                        MediaButtons(size: 16)
                        if m.hasFullControls { toggle("repeat", on: m.repeating, label: L("media.repeat")) { MediaProvider.shared.toggleRepeat() } }
                        if MediaProvider.shared.canLove {
                            toggle("heart.fill", on: MediaProvider.shared.loved, label: L("media.love")) { MediaProvider.shared.toggleLove() }
                        }
                        Button { AudioOutputProvider.shared.refresh(); showOutputs.toggle() } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "airplayaudio").font(.system(size: 12))
                                SwiftUI.Text(AudioOutputProvider.shared.currentName ?? L("media.output")).font(DY.font(11)).lineLimit(1)
                                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                            }
                            .foregroundStyle(DY.fg2)
                        }
                        .buttonStyle(.plain).accessibilityLabel(L("media.output"))
                    }
                    .frame(maxWidth: .infinity)
                    if showOutputs {
                        HStack(alignment: .top, spacing: 8) {
                            OutputList { showOutputs = false }
                            if model.features.isEnabled(.appVolume) { AppMixer() }
                        }
                    }
                    else if let lyrics = LyricsProvider.shared.lyrics { LyricsBlock(lyrics: lyrics, media: m) }
                    if let v = m.volume {
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(DY.fg2)
                            ScrubBar(fraction: Double(v) / 100, color: .white, label: L("media.volume")) { f, done in
                                if done { MediaProvider.shared.setVolume(Int(f * 100)) }
                            }
                            Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(DY.fg2)
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                EmptyCard(symbol: "music.note", text: L("media.empty"))
                QuickPlayRow()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func toggle(_ symbol: String, on: Bool, label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(on ? model.mediaAccent : DY.fg2)
                .frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(PressScale()).accessibilityLabel(label).accessibilityValue(on ? L("a11y.on") : L("a11y.off"))
    }
}

/// Lyric lines, active one in the middle (design D23/M10), with karaoke, romanization and translation (D53).
/// Hidden when nothing was found.
struct LyricsBlock: View {
    var lyrics: Lyrics
    var media: MediaState
    private var model: AppModel { AppModel.shared }
    private var lp: LyricsProvider { LyricsProvider.shared }
    private var prefs: Prefs { Prefs.shared }
    @StateBox private var translation: TranslationSession.Configuration?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            lines
            chips
        }
        .translationTask(translation) { session in
            await Self.translate(session, lyrics: lyrics)
        }
        .onAppear { requestTranslation() }
        .onChange(of: prefs.translate) { requestTranslation() }
        .onChange(of: lyrics) { requestTranslation() }
    }

    private var lines: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let pos = media.livePosition(ctx.date)
            let i = lyrics.index(at: pos)
            VStack(alignment: .leading, spacing: 3) {
                if lyrics.synced {
                    line(i.flatMap { $0 > 0 ? lyrics.lines[$0 - 1].text : nil }, active: false)
                    if let i { activeLine(lyrics.lines[i], pos) } else { line("♪", active: true) }
                    if prefs.romanize, let i, let r = lp.romanized[i] { extra(r) }
                    if prefs.translate, let i, let t = lp.translated[i] { extra(t, italic: true) }
                    line(lyrics.lines[safe: (i ?? -1) + 1]?.text, active: false)
                } else {
                    ForEach(Array(lyrics.lines.prefix(3).enumerated()), id: \.offset) { _, l in line(l.text, active: false) }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: i)
        }
        .accessibilityElement(children: .combine)
    }

    /// Karaoke: words light up one by one when the source has word times; otherwise the whole line at once.
    @ViewBuilder private func activeLine(_ l: Lyrics.Line, _ pos: TimeInterval) -> some View {
        if prefs.karaoke, Prefs.motionAllowed, let words = l.words {
            let lit = Lyrics.litWords(l, at: pos)
            words.enumerated().reduce(SwiftUI.Text("")) { acc, w in
                acc + SwiftUI.Text(w.element.text)
                    .foregroundColor(w.offset < lit ? model.mediaAccent : Color.white.opacity(0.45))
            }
            .font(DY.font(13.5, .semibold)).lineLimit(1)
        } else {
            line(l.text, active: true)
        }
    }

    private func line(_ s: String?, active: Bool) -> some View {
        SwiftUI.Text(s ?? " ").font(active ? DY.font(13.5, .semibold) : DY.font(11.5, .regular))
            .foregroundStyle(active ? model.mediaAccent : Color.white.opacity(0.4)).lineLimit(1)
    }

    private func extra(_ s: String, italic: Bool = false) -> some View {
        SwiftUI.Text(s).font(DY.font(11, .regular)).italic(italic).foregroundStyle(DY.fg2).lineLimit(1)
    }

    private var chips: some View {
        HStack(spacing: 4) {
            if lyrics.lines.contains(where: { $0.words != nil }) { chip(L("lyrics.karaoke"), prefs.karaoke) { prefs.karaoke.toggle() } }
            if !lp.romanized.isEmpty { chip(L("lyrics.romanize"), prefs.romanize) { prefs.romanize.toggle() } }
            chip(L("lyrics.translate"), prefs.translate) { prefs.translate.toggle() }
        }
    }

    private func chip(_ t: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SwiftUI.Text(t).font(DY.font(9.5, .semibold)).foregroundStyle(on ? .black : DY.fg2)
                .padding(.horizontal, 7).frame(height: 16)
                .background(Capsule().fill(on ? Color.white : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .accessibilityValue(on ? L("a11y.on") : L("a11y.off"))
    }

    /// Apple Translation, on the Mac once the language is downloaded; results are kept per song.
    private func requestTranslation() {
        guard prefs.translate, lp.translated.isEmpty, lyrics.lines.count > 0 else { return }
        let target = Locale.Language(identifier: L10n.language)
        if translation == nil { translation = .init(source: nil, target: target) } else { translation?.invalidate() }
    }

    private static func translate(_ session: TranslationSession, lyrics: Lyrics) async {
        guard let key = LyricsProvider.shared.songKey else { return }
        let lines = lyrics.lines.prefix(150).enumerated().filter { !$0.element.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { ($0.offset, $0.element.text) }
        let out = await Self.run(SessionBox(session: session), lines)
        LyricsProvider.shared.storeTranslations(out.filter { lyrics.lines[$0.key].text != $0.value }, for: key)
    }

    /// The session is only used here, for this one batch (it is not Sendable, hence the box).
    private nonisolated static func run(_ box: SessionBox, _ lines: [(Int, String)]) async -> [Int: String] {
        let requests = lines.map { TranslationSession.Request(sourceText: $0.1, clientIdentifier: String($0.0)) }
        guard let responses = try? await box.session.translations(from: requests) else { return [:] }
        var out: [Int: String] = [:]
        for r in responses { if let id = r.clientIdentifier.flatMap(Int.init) { out[id] = r.targetText } }
        return out
    }
}

private nonisolated struct SessionBox: @unchecked Sendable { let session: TranslationSession }

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

struct OutputList: View {
    var done: () -> Void
    private var audio: AudioOutputProvider { AudioOutputProvider.shared }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(audio.devices) { d in
                Button { audio.select(d); done() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: d.symbol).frame(width: 16)
                        SwiftUI.Text(d.name).font(DY.font(12, .regular)).lineLimit(1)
                        Spacer()
                        if d.id == audio.current { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                    }
                    .foregroundStyle(.white).padding(.horizontal, 8).frame(height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
    }
}

/// Volume per app (FR-84, design: under the output list in the same layer).
struct AppMixer: View {
    private var mix: AppVolumeProvider { AppVolumeProvider.shared }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SwiftUI.Text(L("mixer.title")).font(DY.font(10.5, .semibold)).foregroundStyle(DY.fg2)
            if mix.apps.isEmpty { SwiftUI.Text(L("mixer.empty")).font(DY.font(11)).foregroundStyle(DY.fg2) }
            ForEach(mix.apps.prefix(5)) { app in
                HStack(spacing: 8) {
                    if let i = app.icon { Image(nsImage: i).resizable().frame(width: 14, height: 14) }
                    SwiftUI.Text(app.name).font(DY.font(11.5, .regular)).foregroundStyle(.white).lineLimit(1).frame(width: 74, alignment: .leading)
                    ScrubBar(fraction: Double(mix.volume(app.id)), color: .white, label: L("mixer.volume", app.name)) { f, _ in
                        mix.set(app.id, Float(f))
                    }
                    SwiftUI.Text(verbatim: "\(Int((mix.volume(app.id) * 100).rounded()))%").font(DY.mono).foregroundStyle(DY.fg2).frame(width: 34, alignment: .trailing)
                }
                .frame(height: 20)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
        .onAppear { mix.refresh() }
    }
}

/// Pinned Spotify playlists; adding happens in Settings → Media.
struct QuickPlayRow: View {
    private var model: AppModel { AppModel.shared }
    var body: some View {
        if model.quickPlay.isEmpty {
            SwiftUI.Text(L("media.quickPlayEmpty")).font(DY.font(11, .regular)).foregroundStyle(DY.fg2)
        } else {
            HStack(spacing: 6) {
                SwiftUI.Text(L("media.quickPlay")).font(DY.font(11, .semibold)).foregroundStyle(DY.fg2)
                ForEach(model.quickPlay.prefix(4)) { item in
                    NotchButton(title: item.name) { MediaProvider.shared.play(item) }
                }
            }
        }
    }
}

// MARK: Agents (D9, D18)

struct AgentsTab: View {
    private var model: AppModel { AppModel.shared }
    @StateBox private var showHistory = false
    /// Read once when the tab opens, not on every render (it parses settings.json).
    @StateBox private var hooksInstalled = HookSetup.status() == .installed

    var body: some View {
        // Plain stack (not ScrollView): the panel height is fixed and lists are capped.
        VStack(alignment: .leading, spacing: 10) {
            if let p = model.pendingForDisplay, let s = model.agents.sessions[p.sessionID] {
                PermissionCard(pending: p, session: s)
            }
            if showHistory { history } else { sessions }
        }
    }

    @ViewBuilder private var sessions: some View {
        HStack {
            SwiftUI.Text(L("agents.active", model.agents.active.count)).font(DY.font(11, .semibold)).foregroundStyle(DY.fg2)
            Spacer()
            Button(L("agents.history")) { showHistory = true }.buttonStyle(.plain).font(DY.font(11)).foregroundStyle(DY.fg2)
        }
        if model.agents.ordered.isEmpty {
            EmptyCard(symbol: "sparkle", text: hooksInstalled ? L("agents.empty") : L("agents.noHooks"))
        }
        ForEach(model.agents.ordered.prefix(model.pendingForDisplay == nil ? 4 : 2)) { s in SessionRow(session: s) }
        ForEach(model.center.ordered.filter { $0.id.hasPrefix("agent-result-") }) { a in
            HStack(spacing: 10) {
                Image(systemName: a.symbol).foregroundStyle(DY.color(for: a.state)).frame(width: 16)
                SwiftUI.Text(model.displayDetail(a)).font(DY.font(12, .regular)).foregroundStyle(DY.fg).lineLimit(2)
                Spacer()
                if let id = a.url { NotchButton(title: L("button.openProject")) { model.perform(.focusSession(id)) } }
            }
        }
    }

    @ViewBuilder private var history: some View {
        HStack {
            Button { showHistory = false } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).foregroundStyle(DY.fg2)
            SwiftUI.Text(L("history.title")).font(DY.font(12, .semibold)).foregroundStyle(.white)
            Spacer()
            Button(L("button.clear")) { model.center.clearHistory() }.buttonStyle(.plain).font(DY.font(11)).foregroundStyle(DY.fg2)
        }
        if model.center.history.isEmpty { EmptyCard(symbol: "clock", text: L("history.empty")) }
        ForEach(Array(model.center.history.prefix(8).enumerated()), id: \.offset) { _, h in
            HStack(spacing: 10) {
                Image(systemName: h.activity.symbol).font(.system(size: 11)).foregroundStyle(DY.color(for: h.activity.state)).frame(width: 16)
                SwiftUI.Text(model.displayDetail(h.activity)).font(DY.font(12, .regular)).foregroundStyle(DY.fg).lineLimit(1)
                Spacer()
                SwiftUI.Text(h.at.formatted(.dateTime.hour().minute().locale(L10n.locale))).font(DY.font(11)).monospacedDigit().foregroundStyle(DY.fg2)
            }
        }
    }
}

struct PermissionCard: View {
    var pending: PendingPermission
    var session: AgentSessions.Session
    private var model: AppModel { AppModel.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").foregroundStyle(DY.action)
                SwiftUI.Text(AppModel.named(L("agent.needsPermission"), session.agent)).font(DY.font(13, .semibold)).foregroundStyle(.white)
                SwiftUI.Text(model.presentationMode ? appName(session) : "\(session.project) · \(appName(session))").font(DY.font(11.5, .regular)).foregroundStyle(DY.fg2)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = max(0, Int(model.permissionTimeout - ctx.date.timeIntervalSince(pending.createdAt)))
                    SwiftUI.Text(L("permission.releaseIn", left)).font(DY.font(11, .regular)).monospacedDigit().foregroundStyle(DY.fg2)
                }
            }
            HStack(spacing: 6) {
                SwiftUI.Text(pending.tool ?? "").font(DY.font(12, .semibold)).foregroundStyle(DY.action)
                SwiftUI.Text(pending.detail ?? "").font(DY.mono).foregroundStyle(DY.fg).lineLimit(2).textSelection(.enabled)
                Spacer()
                NotchButton(title: L("button.deny"), height: 28) { model.perform(.deny(pending.requestID)) }
                NotchButton(title: L("button.allow"), kind: .primaryAction, height: 28) { model.perform(.allow(pending.requestID)) }
                NotchButton(title: L("button.openTerminal"), height: 28) { model.perform(.releaseToTerminal(pending.requestID)) }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DY.action.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DY.action.opacity(0.35), lineWidth: 1))
    }
}

struct SessionRow: View {
    var session: AgentSessions.Session
    private var model: AppModel { AppModel.shared }

    var body: some View {
        HStack(spacing: 10) {
            status.frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    SwiftUI.Text(model.presentationMode ? L("generic.agent") : session.project).font(DY.font(12.5, .semibold)).foregroundStyle(.white)
                    SwiftUI.Text(appName(session)).font(DY.font(11, .regular)).foregroundStyle(DY.fg2)
                }
                SwiftUI.Text(line).font(DY.mono).foregroundStyle(DY.fg2).lineLimit(1)
            }
            Spacer()
            if let start = session.promptStartedAt, case .working = session.status { Elapsed(since: start) }
            Button { model.perform(.focusSession(session.id)) } label: {
                Image(systemName: "arrow.up.forward.app").font(.system(size: 12)).foregroundStyle(DY.fg2)
            }
            .buttonStyle(PressScale()).accessibilityLabel(L("button.open"))
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var status: some View {
        switch session.status {
        case .working: Spinner()
        case .needsPermission: Image(systemName: "sparkle").foregroundStyle(DY.action)
        case .waitingInput: Image(systemName: "ellipsis.bubble").foregroundStyle(DY.info)
        case .done: Image(systemName: "checkmark").foregroundStyle(DY.ok)
        case .failed: Image(systemName: "xmark").foregroundStyle(DY.fail)
        case .idle: Image(systemName: "moon.zzz").foregroundStyle(DY.fg2)
        }
    }

    private var line: String { AppModel.named(rawLine, session.agent) }

    private var rawLine: String {
        if model.presentationMode { return L("generic.agent") }
        switch session.status {
        case .working(let tool, let detail): return [tool, detail].compactMap { $0 }.joined(separator: " · ")
        case .needsPermission(_, let tool, let detail): return L("agent.needsPermission") + ": " + [tool, detail].compactMap { $0 }.joined(separator: " ")
        case .waitingInput: return L("agent.waiting")
        case .done(_, let summary): return summary ?? L("compact.done")
        case .failed(let m): return m ?? L("agent.failed")
        case .idle: return L("agents.idle")
        }
    }
}

func appName(_ s: AgentSessions.Session) -> String {
    let id = s.appBundleID ?? TerminalFocus.bundleFromTerm(s.termProgram)
    guard let id, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return s.termProgram ?? "Terminal" }
    return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
}

// MARK: Shared bits

/// Thin bar with drag-to-set (seek, volume). Reports the final value when the drag ends.
struct ScrubBar: View {
    var fraction: Double
    var color: Color
    var label: String
    var onChange: (Double, Bool) -> Void

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                ProgressBar(progress: fraction, color: color).frame(height: 4)
                Circle().fill(.white).frame(width: 10, height: 10)
                    .offset(x: max(0, min(g.size.width - 10, g.size.width * fraction - 5)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { onChange(min(1, max(0, $0.location.x / g.size.width)), false) }
                .onEnded { onChange(min(1, max(0, $0.location.x / g.size.width)), true) })
        }
        .frame(height: 14)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(fraction * 100))%")
        .accessibilityAdjustableAction { dir in
            onChange(min(1, max(0, fraction + (dir == .increment ? 0.05 : -0.05))), true)
        }
    }
}

struct Artwork: View {
    var image: NSImage?
    var size: CGFloat
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            else { ZStack { Color.white.opacity(0.08); Image(systemName: "music.note").foregroundStyle(DY.fg2) } }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct EmptyCard: View {
    var symbol: String
    var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(DY.fg2)
            SwiftUI.Text(text).font(DY.font(12, .regular)).foregroundStyle(DY.fg2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }
}
