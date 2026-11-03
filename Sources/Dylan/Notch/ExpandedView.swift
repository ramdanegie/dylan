import AppKit
import AVFoundation
import DylanCore
import SwiftUI

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
                switch model.selectedTab {
                case .home: HomeTab()
                case .media: MediaTab()
                case .clipboard: ClipboardTab()
                case .shelf: ShelfTab()
                case .discord: DiscordTab()
                case .stats: StatsTab()
                case .dev: DevTab()
                case .agents: AgentsTab()
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
        let left = tabs.filter { [.home, .media, .discord, .shelf].contains($0) }
        let right = tabs.filter { ![.home, .media, .discord, .shelf].contains($0) }
        return HStack(spacing: 0) {
            HStack(spacing: 4) { ForEach(left) { tabButton($0) } }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16)
            Color.clear.frame(width: notchWidth)
            HStack(spacing: 4) {
                ForEach(right) { tabButton($0) }
                Button { SettingsWindow.show() } label: {
                    Image(systemName: "gearshape").font(.system(size: 12)).foregroundStyle(DY.fg2).frame(width: 26, height: 22)
                }
                .buttonStyle(PressScale()).accessibilityLabel(L("menu.settings"))
                StatusDots()
            }
            .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 16)
        }
    }

    private func tabButton(_ t: Tab) -> some View {
        let active = model.selectedTab == t
        return Button {
            withAnimation(DY.spring) { model.selectedTab = t }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: t.symbol).font(.system(size: 11, weight: .semibold))
                if active { SwiftUI.Text(t.title).font(DY.font(12, .semibold)) }
            }
            .foregroundStyle(active ? .white : DY.fg2)
            .padding(.horizontal, active ? 10 : 0)
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
            else if model.scratchpadOpen { ScratchpadView().frame(maxHeight: .infinity) }
            else { columns }
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
                .frame(width: 150)
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
                        SwiftUI.Text("\(m.artist) · \(m.source == .spotify ? "Spotify" : "Music")")
                            .font(DY.font(11.5, .regular)).foregroundStyle(DY.fg2).lineLimit(1)
                    }
                }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    VStack(spacing: 3) {
                        ProgressBar(progress: m.duration > 0 ? m.livePosition(ctx.date) / m.duration : 0, color: model.mediaAccent)
                            .frame(height: 3)
                        HStack {
                            ValueText(text: DurationFormat.running(m.livePosition(ctx.date)), color: DY.fg2)
                            Spacer()
                            ValueText(text: DurationFormat.running(m.duration), color: DY.fg2)
                        }
                        .font(.system(size: 10))
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
            if model.features.isEnabled(.reminders) { RemindersList() }
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

struct TimerCard: View {
    @StateBox private var input = ""
    private var model: AppModel { AppModel.shared }

    var body: some View {
        VStack(spacing: 8) {
            if let t = model.timer {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    ZStack {
                        TimerRing(progress: t.progress(now: ctx.date), size: 84)
                        VStack(spacing: 0) {
                            ValueText(text: DurationFormat.running(t.remaining(now: ctx.date))).font(.system(size: 18, weight: .semibold))
                            SwiftUI.Text(t.phase == .timer ? L("timer.timer") : (t.phase == .focus ? L("timer.focus") : L("timer.break")))
                                .font(DY.font(10.5, .regular)).foregroundStyle(DY.fg2)
                        }
                    }
                }
                if t.phase != .timer {
                    SwiftUI.Text(L("timer.cycle", t.focusCount + (t.phase == .focus ? 1 : 0))).font(DY.font(10.5, .regular)).foregroundStyle(DY.fg2)
                }
                HStack(spacing: 6) {
                    NotchButton(title: t.isPaused ? L("button.resume") : L("button.pause")) { model.toggleTimerPause() }
                    NotchButton(title: L("button.reset"), kind: .quiet) { model.stopTimer() }
                }
            } else {
                SwiftUI.Text(L("timer.title")).font(DY.font(11, .semibold)).foregroundStyle(DY.fg2).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    ForEach([5, 10, 25], id: \.self) { m in
                        NotchButton(title: "\(m)m") { model.startTimer(.quick(TimeInterval(m * 60), now: Date())) }
                    }
                }
                NotchButton(title: L("timer.pomodoro"), kind: .primaryNeutral) { model.startTimer(.pomodoro(now: Date())) }
                TextField(L("timer.custom"), text: $input)
                    .textFieldStyle(.plain).font(DY.font(12, .regular)).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(DY.control))
                    .onSubmit {
                        if let d = DurationParser.parse(input) { model.startTimer(.quick(d, now: Date())); input = "" }
                    }
            }
        }
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
            if model.features.isEnabled(.keepAwake) {
                if let k = model.keepAwake {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        NotchButton(title: k.remaining(now: ctx.date).map { L("keepAwake.stopIn", DurationFormat.long($0, language: L10n.language)) }
                                    ?? L("keepAwake.stop")) { model.stopKeepAwake() }
                    }
                } else if DownloadsProvider.shared.active {
                    NotchButton(title: L("keepAwake.untilDownloads")) { model.keepAwakeUntilDownloads = true; model.startKeepAwake(minutes: 0) }
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
                        SwiftUI.Text(m.source == .spotify ? "Spotify" : "Apple Music").font(DY.font(11, .semibold)).foregroundStyle(DY.fg2)
                        SwiftUI.Text(m.title).font(DY.font(17, .semibold)).foregroundStyle(.white).lineLimit(1)
                        SwiftUI.Text("\(m.artist) · \(m.album)").font(DY.font(12.5, .regular)).foregroundStyle(DY.fg2).lineLimit(1)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let pos = scrub ?? m.livePosition(ctx.date)
                        VStack(spacing: 4) {
                            ScrubBar(fraction: m.duration > 0 ? pos / m.duration : 0, color: model.mediaAccent,
                                     label: L("media.position")) { f, done in
                                scrub = f * m.duration
                                if done { MediaProvider.shared.seek(to: f * m.duration); scrub = nil }
                            }
                            HStack {
                                ValueText(text: DurationFormat.running(pos), color: DY.fg2)
                                Spacer()
                                ValueText(text: DurationFormat.running(m.duration), color: DY.fg2)
                            }
                        }
                    }
                    HStack(spacing: 18) {
                        toggle("shuffle", on: m.shuffle, label: L("media.shuffle")) { MediaProvider.shared.toggleShuffle() }
                        MediaButtons(size: 16)
                        toggle("repeat", on: m.repeating, label: L("media.repeat")) { MediaProvider.shared.toggleRepeat() }
                        if MediaProvider.shared.canLove {
                            toggle("heart.fill", on: false, label: L("media.love")) { MediaProvider.shared.toggleLove() }
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
                    if showOutputs { OutputList { showOutputs = false } }
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

/// Three lyric lines, active one in the middle (design D23/M10). Hidden when nothing was found.
struct LyricsBlock: View {
    var lyrics: Lyrics
    var media: MediaState
    private var model: AppModel { AppModel.shared }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let i = lyrics.index(at: media.livePosition(ctx.date))
            VStack(alignment: .leading, spacing: 3) {
                if lyrics.synced {
                    line(i.flatMap { $0 > 0 ? lyrics.lines[$0 - 1].text : nil }, active: false)
                    line(i.map { lyrics.lines[$0].text } ?? "♪", active: true)
                    line(lyrics.lines[safe: (i ?? -1) + 1]?.text, active: false)
                } else {
                    ForEach(Array(lyrics.lines.prefix(3).enumerated()), id: \.offset) { _, l in line(l.text, active: false) }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: i)
        }
        .accessibilityElement(children: .combine)
    }
    private func line(_ s: String?, active: Bool) -> some View {
        SwiftUI.Text(s ?? " ").font(active ? DY.font(13.5, .semibold) : DY.font(11.5, .regular))
            .foregroundStyle(active ? model.mediaAccent : Color.white.opacity(0.4)).lineLimit(1)
    }
}

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
                SwiftUI.Text(L("agent.needsPermission")).font(DY.font(13, .semibold)).foregroundStyle(.white)
                SwiftUI.Text("\(session.project) · \(appName(session))").font(DY.font(11.5, .regular)).foregroundStyle(DY.fg2)
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
                    SwiftUI.Text(session.project).font(DY.font(12.5, .semibold)).foregroundStyle(.white)
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

    private var line: String {
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
