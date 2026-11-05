import AppKit
import DylanCore
import SwiftUI

// Settings for the v1.5 design (D51–D60).

/// Settings → Prayer times (D51).
struct PrayerSettings: View {
    @StateBox private var cityInput = PrayerProvider.shared.city
    private var p: PrayerProvider { PrayerProvider.shared }

    var body: some View {
        FeatureToggles(features: [.prayer])
        Section {
            LabeledContent(L("prayer.city")) {
                TextField("", text: $cityInput, prompt: SwiftUI.Text(L("prayer.cityPrompt")))
                    .frame(minWidth: 200).multilineTextAlignment(.trailing)
                    .onSubmit { p.setCity(cityInput) }
            }
            SwiftUI.Text(status).font(.caption).foregroundStyle(p.lookupFailed ? .orange : .secondary)
            Toggle(L("prayer.countdownToggle"), isOn: Binding(get: { p.countdown }, set: { p.countdown = $0 }))
            Toggle(L("prayer.hijriToggle"), isOn: Binding(get: { p.showHijri }, set: { p.showHijri = $0 }))
        }
        Section {
            Picker(L("prayer.adhan"), selection: Binding(get: { p.adhan }, set: { p.adhan = $0 })) {
                ForEach(PrayerProvider.Adhan.allCases, id: \.self) { SwiftUI.Text(L("prayer.adhan.\($0.rawValue)")).tag($0) }
            }
            .pickerStyle(.segmented)
            LabeledContent(L("prayer.adhanFile")) {
                HStack {
                    SwiftUI.Text(p.adhanFile.map { ($0 as NSString).lastPathComponent } ?? L("prayer.adhanNone")).lineLimit(1).truncationMode(.middle)
                    Button(L("prayer.choose")) { p.chooseAdhanFile() }
                    if p.adhanFile != nil {
                        Button(p.adhanPlaying ? L("prayer.stopAdhan") : L("prayer.test")) { p.adhanPlaying ? p.stopAdhan() : p.playAdhan() }
                    }
                }
            }
            SwiftUI.Text(L("prayer.adhanHint")).font(.caption).foregroundStyle(.secondary)
            Toggle(L("prayer.pauseMusic"), isOn: Binding(get: { p.pauseMusic }, set: { p.pauseMusic = $0 }))
        }
        Section {
            Picker(L("prayer.remind"), selection: Binding(get: { p.remindBefore }, set: { p.remindBefore = $0 })) {
                SwiftUI.Text(L("prayer.remindOff")).tag(0)
                ForEach([5, 10, 15, 20, 30], id: \.self) { SwiftUI.Text(L("prayer.minutes", $0)).tag($0) }
            }
            Stepper(L("prayer.ihtiyat", p.ihtiyat), value: Binding(get: { p.ihtiyat }, set: { p.ihtiyat = $0 }), in: -5...10)
            SwiftUI.Text(L("prayer.methodHint")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var status: String {
        if p.city.isEmpty { return L("prayer.cityHint") }
        if p.lookupFailed { return L("prayer.cityNotFound", p.city) }
        guard let lat = p.latitude, let lon = p.longitude else { return L("prayer.looking") }
        return L("prayer.cityFound", String(format: "%.3f, %.3f", lat, lon))
    }
}

/// Settings → Animations (D54): each one on or off; Reduce Motion turns them all off.
struct AnimationSettings: View {
    private var prefs: Prefs { Prefs.shared }
    var body: some View {
        Section {
            toggle("anim.glow", \.glowLine)
            toggle("anim.line", \.timeLine)
            toggle("anim.stack", \.stacked)
        }
        Section {
            toggle("anim.karaoke", \.karaoke)
            toggle("anim.confetti", \.confetti)
            LabeledContent(L("anim.reduceMotion"), value: Prefs.motionAllowed ? L("a11y.off") : L("a11y.on"))
            SwiftUI.Text(L("anim.reduceMotionHint")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func toggle(_ key: String, _ path: ReferenceWritableKeyPath<Prefs, Bool>) -> some View {
        Toggle(isOn: Binding(get: { prefs[keyPath: path] }, set: { prefs[keyPath: path] = $0 })) {
            SwiftUI.Text(L(key))
            SwiftUI.Text(L(key + ".hint")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Appearance → island style, floating island, position (D59).
struct IslandStyleSettings: View {
    private var prefs: Prefs { Prefs.shared }
    private var hasNotch: Bool { NotchController.shared.layout.geometry.hasNotch }

    var body: some View {
        Section(L("look.title")) {
            Picker(L("look.style"), selection: Binding(get: { prefs.style }, set: { prefs.style = $0; NotchController.shared.relayout() })) {
                ForEach(IslandStyle.allCases) { SwiftUI.Text(L("look.style.\($0.rawValue)")).tag($0) }
            }
            .pickerStyle(.segmented)
            if prefs.style == .color {
                ColorPicker(L("look.color"), selection: Binding(get: { Color(nsColor: NSColor(hex: prefs.styleColor) ?? .black) },
                                                                set: { prefs.styleColor = NSColor($0).hexString }), supportsOpacity: false)
            }
            if prefs.style == .floating {
                LabeledContent(L("look.floatGap", Int(prefs.floatGap))) {
                    Slider(value: Binding(get: { prefs.floatGap }, set: { prefs.floatGap = $0.rounded(); NotchController.shared.relayout() }), in: 0...12).frame(width: 180)
                }
                LabeledContent(L("look.floatWidth", Int(prefs.floatWidth))) {
                    Slider(value: Binding(get: { prefs.floatWidth }, set: { prefs.floatWidth = $0.rounded(); NotchController.shared.relayout() }), in: 0...120).frame(width: 180)
                }
            }
            SwiftUI.Text(L(hasNotch ? "look.notchHint" : "look.pillHint")).font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Toggle(isOn: Binding(get: { prefs.dodgeMouse }, set: { prefs.dodgeMouse = $0 })) {
                SwiftUI.Text(L("look.dodge"))
                SwiftUI.Text(L("look.dodgeHint")).font(.caption).foregroundStyle(.secondary)
            }
            .disabled(hasNotch)
            Button(L("look.resetPosition")) {
                for k in AppModel.store.dictionaryRepresentation().keys where k.hasPrefix("pill.offset.") { AppModel.store.removeObject(forKey: k) }
                NotchController.shared.relayout()
            }
            .disabled(hasNotch)
        }
    }
}

/// Media → lyrics extras (D53) and Focus (D58).
struct LyricsFocusSettings: View {
    private var prefs: Prefs { Prefs.shared }
    var body: some View {
        Section(L("lyrics.title")) {
            Toggle(isOn: Binding(get: { prefs.romanize }, set: { prefs.romanize = $0 })) {
                SwiftUI.Text(L("lyrics.romanizeToggle"))
                SwiftUI.Text(L("lyrics.romanizeHint")).font(.caption).foregroundStyle(.secondary)
            }
            Toggle(isOn: Binding(get: { prefs.translate }, set: { prefs.translate = $0 })) {
                SwiftUI.Text(L("lyrics.translateToggle"))
                SwiftUI.Text(L("lyrics.translateHint")).font(.caption).foregroundStyle(.secondary)
            }
        }
        Section(L("focus.title")) {
            Stepper(L("focus.focusMinutes", prefs.focusMinutes), value: Binding(get: { prefs.focusMinutes }, set: { prefs.focusMinutes = $0 }), in: 5...120, step: 5)
            Stepper(L("focus.shortMinutes", prefs.shortBreakMinutes), value: Binding(get: { prefs.shortBreakMinutes }, set: { prefs.shortBreakMinutes = $0 }), in: 1...30)
            Stepper(L("focus.longMinutes", prefs.longBreakMinutes), value: Binding(get: { prefs.longBreakMinutes }, set: { prefs.longBreakMinutes = $0 }), in: 5...60, step: 5)
            Toggle(L("focus.autoBreak"), isOn: Binding(get: { prefs.autoBreak }, set: { prefs.autoBreak = $0 }))
            Toggle(L("focus.autoFocus"), isOn: Binding(get: { prefs.autoFocus }, set: { prefs.autoFocus = $0 }))
        }
    }
}

/// Live Activity → notification history and Focus (D57).
struct NotificationHistorySettings: View {
    private var prefs: Prefs { Prefs.shared }
    var body: some View {
        Section(L("notifications.historyTitle")) {
            Picker(L("notifications.keep"), selection: Binding(get: { prefs.historyDays }, set: { prefs.historyDays = $0 })) {
                SwiftUI.Text(L("notifications.keep1")).tag(1)
                SwiftUI.Text(L("notifications.keep7")).tag(7)
            }
            .pickerStyle(.segmented)
            Toggle(isOn: Binding(get: { prefs.holdDuringFocus }, set: { prefs.holdDuringFocus = $0 })) {
                SwiftUI.Text(L("notifications.holdFocus"))
                SwiftUI.Text(L("notifications.holdFocusHint")).font(.caption).foregroundStyle(.secondary)
            }
            SwiftUI.Text(L("notifications.historyHint")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Devices → mic mute and airplane mode (D60).
struct QuickToggleSettings: View {
    private var model: AppModel { AppModel.shared }
    var body: some View {
        if model.features.isEnabled(.quickToggles) {
            Section {
                LabeledContent(L("quick.micShortcut"), value: "⌃⌥M")
                LabeledContent(L("quick.airplaneShortcut"), value: "⌃⌥⇧A")
                SwiftUI.Text(L("quick.hint")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Utilities → Home modules (D59): which cards show, the flashcard deck and radio stations.
struct ModuleSettings: View {
    @StateBox private var stationName = ""
    @StateBox private var stationURL = ""
    private var prefs: Prefs { Prefs.shared }
    private var cards: FlashcardStore { FlashcardStore.shared }
    private var radio: RadioPlayer { RadioPlayer.shared }

    var body: some View {
        Section(L("module.title")) {
            ForEach(HomeModule.allCases) { m in
                Toggle(isOn: Binding(get: { prefs.modules.contains(m) },
                                     set: { on in prefs.modules = on ? prefs.modules + [m] : prefs.modules.filter { $0 != m } })) {
                    SwiftUI.Text(L("module.\(m.rawValue)"))
                    SwiftUI.Text(L("module.\(m.rawValue).hint")).font(.caption).foregroundStyle(.secondary)
                }
            }
            SwiftUI.Text(L("module.limitHint")).font(.caption).foregroundStyle(.secondary)
        }
        Section(L("module.flashcards")) {
            LabeledContent(L("flash.deck"), value: cards.deck.map { L("flash.deckInfo", $0.name, $0.cards.count, $0.learned) } ?? L("flash.noDeck"))
            HStack {
                Button(L("flash.import")) { cards.importFile() }
                if cards.deck != nil { Button(L("flash.remove"), role: .destructive) { cards.remove() } }
            }
            SwiftUI.Text(L("flash.importHint")).font(.caption).foregroundStyle(.secondary)
        }
        Section(L("module.radio")) {
            ForEach(radio.stations) { s in
                LabeledContent(s.name) {
                    Button(L("button.remove")) { radio.stations.removeAll { $0 == s } }
                }
            }
            LabeledContent(L("radio.name")) { TextField("", text: $stationName).frame(minWidth: 180) }
            LabeledContent(L("radio.url")) { TextField("", text: $stationURL, prompt: SwiftUI.Text("https://…")).frame(minWidth: 240) }
            Button(L("radio.add")) {
                let url = stationURL.trimmingCharacters(in: .whitespaces)
                guard !stationName.isEmpty, let u = URL(string: url), u.scheme?.lowercased() == "https", u.host != nil else { return }
                radio.stations.append(.init(name: stationName, url: url))
                stationName = ""; stationURL = ""
            }
            SwiftUI.Text(L("radio.hint")).font(.caption).foregroundStyle(.secondary)
        }
    }
}
