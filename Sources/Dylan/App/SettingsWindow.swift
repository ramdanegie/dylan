import AppKit
import DylanCore
import ServiceManagement
import SwiftUI

/// Settings (PRD §F14, design D16/D36). Developer sections only appear in the Developer profile.
enum SettingsWindow {
    nonisolated(unsafe) private static var window: NSWindow?

    static func show(section: SettingsSection = .general) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 660),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = L("settings.title")
            // D50: the sidebar runs up under the traffic lights; the page banner carries the title.
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.minSize = NSSize(width: 780, height: 520)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.contentView = NSHostingView(rootView: SettingsView(selection: section))
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, animations, liveActivity, media, prayer, discord, devices, thermal, storage, faceUnlock, utilities, clipboard, screenshot, agents, terminal, features, about
    var id: String { rawValue }
    /// Sidebar groups by purpose (FR-104).
    enum Group: CaseIterable { case basics, notch, system, tools, developer, info
        var title: String? {
            switch self {
            case .basics: return nil
            case .notch: return L("settings.group.notch")
            case .system: return L("settings.group.system")
            case .tools: return L("settings.group.tools")
            case .developer: return L("settings.developer")
            case .info: return nil   // D50: Features and About sit under an unlabeled gap
            }
        }
    }

    var group: Group {
        switch self {
        case .general, .appearance, .animations: return .basics
        case .liveActivity, .media, .prayer, .discord: return .notch
        case .devices, .thermal, .storage, .faceUnlock: return .system
        case .utilities, .clipboard, .screenshot: return .tools
        case .agents, .terminal: return .developer
        case .features, .about: return .info
        }
    }

    var isDeveloper: Bool { group == .developer }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .animations: return "sparkles"
        case .prayer: return "moon.stars"
        case .liveActivity: return "bell.badge"
        case .media: return "music.note"
        case .discord: return "headphones"
        case .devices: return "battery.100percent.bolt"
        case .thermal: return "fan"
        case .storage: return "internaldrive"
        case .utilities: return "wrench.and.screwdriver"
        case .clipboard: return "doc.on.clipboard"
        case .screenshot: return "camera.viewfinder"
        case .faceUnlock: return "faceid"
        case .agents: return "sparkle"
        case .terminal: return "terminal"
        case .features: return "checklist"
        case .about: return "info.circle"
        }
    }
    var title: String { L("settings.section.\(rawValue)") }

    // MARK: D50 page art

    var orbs: (UInt32, UInt32) {
        typealias O = Art.Orb
        switch self {
        case .general, .features, .about: return (O.teal, O.sand)
        case .appearance: return (O.lilac, O.teal)
        case .animations: return (O.lilac, O.rose)
        case .prayer: return (O.teal, O.green)
        case .liveActivity, .agents: return (O.teal, O.sky)
        case .media: return (O.sand, O.rose)
        case .discord: return (O.lilac, O.sky)
        case .devices: return (O.green, O.teal)
        case .thermal: return (O.sky, O.teal)
        case .storage: return (O.butter, O.sand)
        case .faceUnlock: return (O.rose, O.lilac)
        case .utilities: return (O.sand, O.butter)
        case .clipboard: return (O.teal, O.green)
        case .screenshot: return (O.sand, O.lilac)
        case .terminal: return (O.green, O.sky)
        }
    }

    /// Orb positions alternate sides from page to page (D50).
    var orbX: (CGFloat, CGFloat) {
        switch self {
        case .general: return (0.28, 0.74)
        case .appearance: return (0.70, 0.26)
        case .animations: return (0.26, 0.74)
        case .prayer: return (0.30, 0.72)
        case .liveActivity: return (0.24, 0.78)
        case .media: return (0.76, 0.30)
        case .discord: return (0.30, 0.72)
        case .devices: return (0.26, 0.76)
        case .thermal: return (0.72, 0.24)
        case .storage: return (0.30, 0.70)
        case .faceUnlock: return (0.74, 0.28)
        case .utilities: return (0.26, 0.72)
        case .clipboard: return (0.70, 0.30)
        case .screenshot: return (0.28, 0.74)
        case .agents: return (0.72, 0.26)
        case .terminal: return (0.26, 0.76)
        case .features: return (0.28, 0.72)
        case .about: return (0.30, 0.70)
        }
    }

    var eyebrow: String { L("settings.eyebrow") + (group.title.map { " · " + $0.uppercased() } ?? "") }

    /// The small live status inside the banner's island.
    var island: String {
        let m = AppModel.shared
        switch self {
        case .general: return "Dylan"
        case .appearance: return "Aa"
        case .animations: return "✦"
        case .prayer:
            let p = PrayerProvider.shared
            guard let n = p.next else { return L("prayer.short") }
            return p.name(n.prayer, on: n.at) + " " + PrayerProvider.clock(n.at)
        case .liveActivity: return Date().formatted(date: .omitted, time: .shortened)
        case .media: return m.presentationMode ? "♪" : m.media.map { "♪ " + $0.title } ?? "♪"
        case .discord: return DiscordProvider.shared.connected ? L("discord.connected") : "Discord"
        case .devices: return m.battery.map { "\($0.percent)%" } ?? "Mac"
        case .thermal: return FanProvider.shared.format(FanProvider.shared.cpu)
        case .storage: return L("storage.island", StorageProvider.bytes(StorageProvider.shared.free))
        case .faceUnlock: return L(FaceUnlockProvider.shared.enabled ? "faceUnlock.island.on" : "faceUnlock.island.off")
        case .utilities: return m.colorHistory.first ?? "#00838A"
        case .clipboard: return "⌃⌥V"
        case .screenshot:
            if ScreenRecorder.shared.isRecording { return "● REC" }
            return NSScreen.main.map { "\(Int($0.frame.width))×\(Int($0.frame.height))" } ?? "⌥⇧1"
        case .agents: return "Claude Code"
        case .terminal: return "zsh"
        case .features:
            let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
            return "\(FeatureSupport.all.filter { $0.status(macOSMajor: major) == .available }.count)"
        case .about: return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        }
    }
}

/// Banner + serif title at the top of every Settings page (D50).
struct SettingsPageHeader: View {
    var section: SettingsSection
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ArtBanner(orbs: section.orbs, x: section.orbX, island: section.island)
            ArtTitle(eyebrow: section.eyebrow, title: L("settings.page.\(section.rawValue).title"),
                     italic: L("settings.page.\(section.rawValue).italic"), detail: L("settings.page.\(section.rawValue).detail"))
        }
        .padding(.horizontal, -4).padding(.bottom, 6)   // full width like the cards
        .textCase(nil)
        .foregroundStyle(.primary)
    }
}

struct SidebarRow: View {
    var section: SettingsSection
    var selected: Bool
    var pick: () -> Void
    @StateBox private var hover = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 11) {
                Image(systemName: section.symbol).symbolRenderingMode(.hierarchical).foregroundStyle(Art.accent)
                    .font(.system(size: 14)).frame(width: 18)
                SwiftUI.Text(section.title).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Art.selected : hover ? Art.selected.opacity(0.5) : .clear)
                    .shadow(color: selected && scheme == .light ? Color(nsColor: Art.hex(0x3C2814, 0.1)) : .clear, radius: 1.5, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SettingsView: View {
    @StateBox var selection: SettingsSection
    private var model: AppModel { AppModel.shared }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Art.line).frame(width: 0.5).ignoresSafeArea()
            Form {
                Section {} header: { SettingsPageHeader(section: selection) }
                detail
            }
            .formStyle(ArtFormStyle())
            .background(Art.content.ignoresSafeArea())
            .id(selection)   // a new page starts at its banner
        }
        .tint(Art.accent)
        .frame(minWidth: 780, minHeight: 520)
    }

    /// D50 sidebar: warm neutral, mono group labels, teal hierarchical symbols, the active page as a white card.
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(SettingsSection.Group.allCases.filter { $0 != .developer || model.isDeveloper }.enumerated()), id: \.element) { n, g in
                    if let title = g.title {
                        SwiftUI.Text(title.uppercased()).font(.system(size: 10, design: .monospaced)).tracking(1.4).foregroundStyle(Art.ink3)
                            .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 5)
                            .accessibilityAddTraits(.isHeader)
                    } else if n > 0 {
                        Spacer().frame(height: 14)
                    }
                    ForEach(SettingsSection.allCases.filter { $0.group == g }) { s in
                        SidebarRow(section: s, selected: s == selection) { selection = s }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 16)
        }
        .scrollIndicators(.never)
        .frame(width: 232)
        .background(Art.side.ignoresSafeArea())
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .general: GeneralSettings()
        case .appearance: AppearanceSettings()
        case .animations: AnimationSettings()
        case .prayer: PrayerSettings()
        case .liveActivity: LiveActivitySettings(); NotificationHistorySettings()
        case .media:
            FeatureToggles(features: [.media, .otherPlayers, .lyrics, .visualizer, .appVolume, .meeting, .timeToLeave, .reminders, .timer])
            if model.features.isEnabled(.otherPlayers) {
                Section { Button(L("otherPlayers.allow")) { OtherPlayersProvider.shared.requestAccess() } }
            }
            LyricsFocusSettings()
            QuickPlaySettings()
        case .devices:
            FeatureToggles(features: [.battery, .bluetooth, .privacy, .focus, .keepAwake, .hud, .quickToggles])
            QuickToggleSettings()
            if model.features.isEnabled(.focus), FocusProvider.shared.blocked {
                Section {
                    SwiftUI.Text(L("focus.blocked")).font(.caption).foregroundStyle(.orange)
                    Button(L("focus.openFullDiskAccess")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!)
                    }
                }
            }
            KeepAwakeSettings()
        case .utilities: UtilitySettings(); ModuleSettings()
        case .discord: DiscordSettings()
        case .clipboard: ClipboardSettings()
        case .screenshot: ScreenshotSettings()
        case .faceUnlock: FaceUnlockSettings()
        case .thermal: ThermalSettings()
        case .storage: StorageSettings()
        case .agents: AgentSettings()
        case .terminal: TerminalSettings()
        case .features: FeatureSupportSettings()
        case .about: AboutSettings()
        }
    }
}

struct GeneralSettings: View {
    @StateBox private var askRelaunch = false
    @StateBox private var loginItem = SMAppService.mainApp.status == .enabled
    private var model: AppModel { AppModel.shared }

    var body: some View {
        Section {
            Picker(L("settings.language"), selection: Binding(get: { model.language }, set: { model.language = $0; askRelaunch = true })) {
                SwiftUI.Text(L("language.system", Locale.current.localizedString(forLanguageCode: Locale.preferredLanguages.first ?? "en") ?? "")).tag(LanguageChoice.system)
                SwiftUI.Text("Bahasa Indonesia").tag(LanguageChoice.indonesian)
                SwiftUI.Text("English").tag(LanguageChoice.english)
            }
            SwiftUI.Text(L("settings.languageHint")).font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Picker(L("settings.profile"), selection: Binding(get: { model.features.profile }, set: { model.features.profile = $0 })) {
                SwiftUI.Text(L("profile.general")).tag(Profile.general)
                SwiftUI.Text(L("profile.developer")).tag(Profile.developer)
            }
            .pickerStyle(.segmented)
            SwiftUI.Text(L("settings.profileHint")).font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Toggle(L("settings.loginItem"), isOn: Binding(get: { loginItem }, set: { on in
                do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister(); loginItem = on }
                catch { model.lastError = error.localizedDescription }
            }))
            LabeledContent(L("settings.hotkeyOpen"), value: "⌃⌥Space")
            LabeledContent(L("settings.hotkeyPresentation"), value: "⌃⌥⌘H")
        }
        .alert(L("language.relaunchTitle"), isPresented: $askRelaunch) {
            Button(L("button.later"), role: .cancel) {}
            Button(L("button.relaunch")) { App.relaunch() }
        } message: { SwiftUI.Text(L("language.relaunchBody")) }
    }
}

struct AppearanceSettings: View {
    @StateBox private var newApp = ""
    private var model: AppModel { AppModel.shared }
    var body: some View {
        Section(L("theme.title")) {
            Toggle(L("theme.accent"), isOn: Binding(get: { model.accentFromArtwork }, set: { model.accentFromArtwork = $0 }))
            Toggle(L("theme.small"), isOn: Binding(get: { model.smallCompact }, set: { model.smallCompact = $0; NotchController.shared.relayout() }))
        }
        IslandStyleSettings()
        Section(L("theme.hideFor")) {
            ForEach(model.hideForApps, id: \.self) { id in
                HStack { SwiftUI.Text(id); Spacer(); Button(L("shelf.remove")) { model.hideForApps.removeAll { $0 == id } } }
            }
            HStack {
                Picker(L("theme.pickApp"), selection: $newApp) {
                    SwiftUI.Text("—").tag("")
                    ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleIdentifier).sorted(), id: \.self) { SwiftUI.Text($0).tag($0) }
                }
                Button(L("media.quickPlayAdd")) { if !newApp.isEmpty, !model.hideForApps.contains(newApp) { model.hideForApps.append(newApp); newApp = "" } }
                    .disabled(newApp.isEmpty)
            }
        }
        Section {
            Toggle(L("settings.duo"), isOn: Binding(get: { model.duo }, set: { model.duo = $0 }))
            LabeledContent(L("settings.hoverDelay")) {
                Slider(value: Binding(get: { model.hoverDelay }, set: { model.hoverDelay = $0 }), in: 0...0.6, step: 0.05)
                SwiftUI.Text("\(Int(model.hoverDelay * 1000)) ms").monospacedDigit().frame(width: 60, alignment: .trailing)
            }
        }
    }
}

struct LiveActivitySettings: View {
    private var model: AppModel { AppModel.shared }
    var body: some View {
        Section {
            Toggle(L("settings.presentation"), isOn: Binding(get: { model.presentationMode }, set: { _ in model.togglePresentation() }))
            SwiftUI.Text(L("settings.presentationHint")).font(.caption).foregroundStyle(.secondary)
            FeatureToggles(features: [.autoPresentation, .lockScreen])
        }
        Section(L("notifications.title")) {
            FeatureToggles(features: [.notifications])
            if model.features.isEnabled(.notifications) {
                if !AXIsProcessTrusted() {
                    Button(L("notifications.allowAccessibility")) {
                        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                    }
                }
                // Fields keep a visible label: under the D50 form style a TextField title is only a placeholder.
                LabeledContent(L("notifications.apps")) {
                    TextField("", text: Binding(get: { model.notificationApps.joined(separator: ", ") },
                                                set: { model.notificationApps = $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                        .frame(minWidth: 240)
                }
                SwiftUI.Text(L("notifications.appsHint")).font(.caption).foregroundStyle(.secondary)
            }
        }
        Section(L("settings.history")) {
            Button(L("button.clearHistory")) { model.center.clearHistory() }
        }
    }
}

struct FeatureToggles: View {
    var features: [Feature]
    private var model: AppModel { AppModel.shared }
    var body: some View {
        Section {
            ForEach(features, id: \.self) { f in
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(L("feature.\(f.rawValue)"), isOn: Binding(get: { model.features.isEnabled(f) },
                                                                    set: { model.features.toggles[f] = $0 }))
                    SwiftUI.Text(L("feature.\(f.rawValue).hint")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        if features.contains(.meeting), CalendarProvider.shared.status != .fullAccess {
            Section { Button(L("button.allowCalendar")) { CalendarProvider.shared.start(requestAccess: true) } }
        }
    }
}

struct DiscordSettings: View {
    @StateBox private var secret = ""
    private var model: AppModel { AppModel.shared }
    private var d: DiscordProvider { DiscordProvider.shared }
    var body: some View {
        FeatureToggles(features: [.discord])
        Section(L("discord.status")) {
            LabeledContent("Client ID") {
                TextField("", text: Binding(get: { model.discordClientID }, set: { model.discordClientID = $0.filter(\.isNumber) }))
                    .multilineTextAlignment(.trailing).frame(minWidth: 200)
            }
            SecureField(L("discord.secret"), text: $secret)
                .onSubmit { Keychain.set(secret, "discord.secret"); secret = "" }
            SwiftUI.Text(L("discord.secretHint")).font(.caption).foregroundStyle(.secondary)
            LabeledContent(L("discord.connection")) {
                SwiftUI.Text(d.connected && d.state.authenticated ? L("discord.connected") : (d.status ?? L("discord.notConnected")))
                    .foregroundStyle(d.connected && d.state.authenticated ? .green : .secondary)
            }
            HStack {
                Button(L("discord.connect")) { d.stop(); d.start() }.disabled(model.discordClientID.count < 15)
                Button(L("discord.signOut")) { d.signOut() }
            }
        }
        Section {
            Toggle(L("discord.showMessages"), isOn: Binding(get: { model.discordMessages }, set: { model.discordMessages = $0 }))
            SwiftUI.Text(L("discord.namesHidden")).font(.caption).foregroundStyle(.secondary)
        }
        Section(L("discord.simpleTitle")) {
            LabeledContent(L("discord.toggleMute")) {
                TextField("", text: Binding(get: { model.discordMuteKey }, set: { model.discordMuteKey = $0 })).multilineTextAlignment(.trailing).frame(minWidth: 160)
            }
            LabeledContent(L("discord.toggleDeafen")) {
                TextField("", text: Binding(get: { model.discordDeafKey }, set: { model.discordDeafKey = $0 })).multilineTextAlignment(.trailing).frame(minWidth: 160)
            }
            SwiftUI.Text(L("discord.simpleHint")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct QuickPlaySettings: View {
    @StateBox private var link = ""
    @StateBox private var name = ""
    private var model: AppModel { AppModel.shared }
    var body: some View {
        Section(L("media.quickPlay")) {
            ForEach(model.quickPlay) { item in
                HStack {
                    SwiftUI.Text(item.name)
                    SwiftUI.Text(item.uri).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("shelf.remove")) { model.quickPlay.removeAll { $0 == item } }
                }
            }
            HStack {
                TextField(L("media.quickPlayLink"), text: $link)
                TextField(L("media.quickPlayName"), text: $name).frame(width: 140)
                Button(L("media.quickPlayAdd")) {
                    guard let uri = SpotifyLink.uri(from: link) else { return }
                    let label = name.trimmingCharacters(in: .whitespaces)
                    model.quickPlay.append(QuickPlayItem(uri: uri, name: label.isEmpty ? L("media.playlist") : label))
                    link = ""; name = ""
                }
                .disabled(SpotifyLink.uri(from: link) == nil)
            }
            SwiftUI.Text(L("media.quickPlayHint")).font(.caption).foregroundStyle(.secondary)
        }
        SpotifyAccountSettings()
    }
}

/// FR-64: the user's own Spotify app (developer.spotify.com) with the loopback redirect below.
struct SpotifyAccountSettings: View {
    private var model: AppModel { AppModel.shared }
    private var account: SpotifyAccount { SpotifyAccount.shared }
    var body: some View {
        Section(L("spotify.account")) {
            SwiftUI.Text(L("spotify.accountHint")).font(.caption).foregroundStyle(.secondary)
            LabeledContent("Client ID") {
                TextField("", text: Binding(get: { model.spotifyClientID }, set: { model.spotifyClientID = $0 })).disabled(account.connected).frame(minWidth: 240)
            }
            HStack {
                SwiftUI.Text(SpotifyAPI.redirectURI).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button(L("button.copy")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(SpotifyAPI.redirectURI, forType: .string) }
            }
            HStack {
                if account.connected {
                    SwiftUI.Text(L("spotify.connected")).foregroundStyle(.green)
                    Spacer()
                    Button(L("discord.signOut")) { account.disconnect() }
                } else {
                    Button(L("spotify.connect")) { account.connect() }.disabled(account.clientID.isEmpty)
                }
            }
            if let s = account.status { SwiftUI.Text(s).font(.caption).foregroundStyle(.secondary) }
            ForEach(account.playlists, id: \.uri) { p in
                HStack {
                    SwiftUI.Text(p.name)
                    if let d = p.detail { SwiftUI.Text(d).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button(L("media.quickPlayAdd")) { model.quickPlay.append(QuickPlayItem(uri: p.uri, name: p.name)) }
                        .disabled(model.quickPlay.contains { $0.uri == p.uri })
                }
            }
        }
    }
}

struct KeepAwakeSettings: View {
    private var model: AppModel { AppModel.shared }
    var body: some View {
        Section(L("keepAwake.title")) {
            Picker(L("keepAwake.default"), selection: Binding(get: { model.keepAwakeMinutes }, set: { model.keepAwakeMinutes = $0 })) {
                SwiftUI.Text("15 m").tag(15)
                SwiftUI.Text(DurationFormat.long(3600, language: L10n.language)).tag(60)
                SwiftUI.Text(L("keepAwake.forever")).tag(0)
            }
            Picker(L("keepAwake.stopBelow"), selection: Binding(get: { model.keepAwakeStopBelow }, set: { model.keepAwakeStopBelow = $0 })) {
                SwiftUI.Text(L("keepAwake.never")).tag(0)
                SwiftUI.Text("10%").tag(10)
                SwiftUI.Text("20%").tag(20)
                SwiftUI.Text("30%").tag(30)
            }
        }
    }
}

struct ClipboardSettings: View {
    @StateBox private var cleared = false
    private var model: AppModel { AppModel.shared }
    var body: some View {
        FeatureToggles(features: [.clipboard])
        Section {
            LabeledContent(L("color.hotkey"), value: "⌃⌥V")
            Toggle(L("clipboard.clearOnQuit"), isOn: Binding(get: { model.clearClipboardOnQuit }, set: { model.clearClipboardOnQuit = $0 }))
            HStack {
                Button(L("clipboard.clearAll")) { ClipboardProvider.shared.clearAll(); cleared = true }
                if cleared { SwiftUI.Text(L("clipboard.cleared")).font(.caption).foregroundStyle(.secondary) }
            }
        }
        Section(L("clipboard.protection")) {
            SwiftUI.Text(L("clipboard.protectionBody")).font(.caption).foregroundStyle(.secondary)
            LabeledContent(L("clipboard.ignoredApps")) {
                SwiftUI.Text(ClipboardProvider.shared.ignoredApps.sorted().map { $0.split(separator: ".").last.map(String.init) ?? $0 }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct UtilitySettings: View {
    private var model: AppModel { AppModel.shared }
    var body: some View {
        FeatureToggles(features: [.shelf, .colorPicker, .weather, .downloads, .scratchpad, .mirror])
        Section(L("weather.title")) {
            LabeledContent(L("weather.city")) {
                TextField("", text: Binding(get: { model.weatherCity }, set: { model.weatherCity = $0 }))
                    .onSubmit { WeatherProvider.shared.cityChanged() }.frame(minWidth: 200)
            }
            SwiftUI.Text(L("weather.privacy")).font(.caption).foregroundStyle(.secondary)
        }
        Section("Shelf") {
            Toggle(L("shelf.screenshots"), isOn: Binding(get: { model.screenshotsToShelf }, set: { model.screenshotsToShelf = $0 }))
            LabeledContent("CLI", value: "dylan shelf add <file…>")
        }
        Section(L("color.title")) {
            LabeledContent(L("color.hotkey"), value: "⌃⌥C")
            Picker(L("color.format"), selection: Binding(get: { model.colorFormat }, set: { model.colorFormat = $0 })) {
                SwiftUI.Text("HEX").tag("hex")
                SwiftUI.Text("RGB").tag("rgb")
                SwiftUI.Text("HSL").tag("hsl")
                if model.isDeveloper { SwiftUI.Text("SwiftUI").tag("swiftui") }
            }
            SwiftUI.Text(L("color.formatHint")).font(.caption).foregroundStyle(.secondary)
            if !model.colorHistory.isEmpty {
                LabeledContent(L("color.history")) {
                    HStack(spacing: 4) {
                        ForEach(model.colorHistory.prefix(10), id: \.self) { hex in
                            let c = PickedColor(hex: hex)
                            Button {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hex, forType: .string)
                            } label: {
                                RoundedRectangle(cornerRadius: 4).fill(Color(red: c?.r ?? 0, green: c?.g ?? 0, blue: c?.b ?? 0))
                                    .frame(width: 18, height: 18)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.4)))
                            }
                            .buttonStyle(.plain).help(hex).accessibilityLabel(hex)
                        }
                    }
                }
            }
        }
    }
}

/// D22: Touch ID for sudo. Dylan only checks and shows the command; it never writes to /etc.
struct TouchIDSudoCard: View {
    @StateBox private var sudoLocal: String?
    @StateBox private var multiplexer = false
    var body: some View {
        Section(L("touchid.title")) {
            LabeledContent(L("touchid.status")) {
                SwiftUI.Text(TouchIDSudo.isEnabled(sudoLocal: sudoLocal) ? L("terminal.active") : L("terminal.inactive"))
                    .foregroundStyle(TouchIDSudo.isEnabled(sudoLocal: sudoLocal) ? .green : .secondary)
            }
            if !TouchIDSudo.isEnabled(sudoLocal: sudoLocal) {
                SwiftUI.Text(L("touchid.body")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    SwiftUI.Text(TouchIDSudo.enableCommand).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button(L("button.copy")) {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(TouchIDSudo.enableCommand, forType: .string)
                    }
                }
            }
            if TouchIDSudo.needsReattach(sudoLocal: sudoLocal, multiplexerRunning: multiplexer) {
                SwiftUI.Text(L("touchid.tmux")).font(.caption).foregroundStyle(.orange)
            }
            SwiftUI.Text(L("touchid.persist")).font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            // Read once per visit, not on every render.
            sudoLocal = try? String(contentsOfFile: "/etc/pam.d/sudo_local", encoding: .utf8)
            multiplexer = ["tmux", "screen"].contains { Shell.run("/usr/bin/pgrep", ["-x", $0]).map { !$0.isEmpty } == true }
        }
    }
}

struct AgentSettings: View {
    @StateBox private var preview: HookSetup.Preview?
    @StateBox private var codexPreview: HookSetup.Preview?
    @StateBox private var codexInstalled = HookSetup.codexInstalled
    @StateBox private var otherPreview: (HookSetup.Preview, URL)?
    @StateBox private var cursorInstalled = HookSetup.cursorInstalled
    @StateBox private var opencodeInstalled = HookSetup.opencodeInstalled
    @StateBox private var status = HookSetup.status()
    @StateBox private var message: String?
    private var model: AppModel { AppModel.shared }

    var body: some View {
        Section("Claude Code") {
            LabeledContent(L("hooks.label")) {
                SwiftUI.Text(statusText).foregroundStyle(status == .installed ? .green : .secondary)
            }
            HStack {
                Button(status == .installed ? L("hooks.reinstall") : L("hooks.install")) { open(HookSetup.previewInstall) }
                if status != .notInstalled { Button(L("hooks.uninstall")) { open(HookSetup.previewUninstall) } }
            }
            if let message { SwiftUI.Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        Section(L("codex.title")) {
            LabeledContent("notify · ~/.codex/config.toml") {
                SwiftUI.Text(codexInstalled ? L("hooks.installed") : L("hooks.notInstalled")).foregroundStyle(codexInstalled ? .green : .secondary)
            }
            Button(codexInstalled ? L("hooks.uninstall") : L("codex.install")) {
                do { (codexPreview, _) = try HookSetup.previewCodex(install: !codexInstalled) } catch { message = error.localizedDescription }
            }
        }
        Section(L("agentsOther.title")) {
            SwiftUI.Text(L("agentsOther.body")).font(.caption).foregroundStyle(.secondary)
            LabeledContent("Cursor · ~/.cursor/hooks.json") {
                HStack {
                    SwiftUI.Text(cursorInstalled ? L("hooks.installed") : L("hooks.notInstalled")).foregroundStyle(cursorInstalled ? .green : .secondary)
                    Button(cursorInstalled ? L("hooks.uninstall") : L("hooks.install")) {
                        do { otherPreview = (try HookSetup.previewCursor(install: !cursorInstalled), HookSetup.cursorURL) } catch { message = error.localizedDescription }
                    }
                    .disabled(!cursorInstalled && !HookSetup.cursorAvailable)
                }
            }
            LabeledContent("OpenCode · ~/.config/opencode/plugins") {
                HStack {
                    SwiftUI.Text(opencodeInstalled ? L("hooks.installed") : L("hooks.notInstalled")).foregroundStyle(opencodeInstalled ? .green : .secondary)
                    Button(opencodeInstalled ? L("hooks.uninstall") : L("hooks.install")) {
                        otherPreview = (HookSetup.previewOpenCode(install: !opencodeInstalled), HookSetup.opencodeURL)
                    }
                    .disabled(!opencodeInstalled && !HookSetup.opencodeAvailable)
                }
            }
        }
        Section(L("mcp.title")) {
            SwiftUI.Text(L("mcp.body")).font(.caption).foregroundStyle(.secondary)
            HStack {
                SwiftUI.Text(HookSetup.mcpCommand).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).lineLimit(2)
                Spacer()
                Button(L("button.copy")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(HookSetup.mcpCommand, forType: .string) }
            }
        }
        Section(L("settings.permissions")) {
            Toggle(L("settings.answerFromNotch"), isOn: Binding(get: { model.answerPermissionsFromNotch }, set: { model.answerPermissionsFromNotch = $0 }))
            SwiftUI.Text(L("settings.answerFromNotchHint")).font(.caption).foregroundStyle(.secondary)
            Stepper(L("settings.releaseAfter", Int(model.permissionTimeout)),
                    value: Binding(get: { model.permissionTimeout }, set: { model.permissionTimeout = $0 }), in: 10...50, step: 5)
            Toggle(L("settings.permissionSound"), isOn: Binding(get: { model.permissionSound }, set: { model.permissionSound = $0 }))
        }
        .sheet(item: Binding(get: { preview.map(IdentifiedPreview.init) }, set: { preview = $0?.p })) { p in
            DiffSheet(preview: p.p) { approved in
                if approved {
                    do {
                        let backup = try HookSetup.apply(p.p)
                        message = backup.map { L("hooks.backup", $0.lastPathComponent) } ?? L("hooks.written")
                    } catch { message = error.localizedDescription }
                }
                preview = nil
                status = HookSetup.status()
            }
        }
        .sheet(item: Binding(get: { otherPreview.map { IdentifiedPreview(p: $0.0) } }, set: { if $0 == nil { otherPreview = nil } })) { p in
            DiffSheet(preview: p.p, title: otherPreview.map { "~/" + $0.1.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path + "/", with: "") } ?? "") { approved in
                if approved, let url = otherPreview?.1 {
                    do { try HookSetup.applyFile(p.p, to: url); message = L("hooks.written") } catch { message = error.localizedDescription }
                }
                otherPreview = nil
                cursorInstalled = HookSetup.cursorInstalled
                opencodeInstalled = HookSetup.opencodeInstalled
            }
        }
        .sheet(item: Binding(get: { codexPreview.map(IdentifiedPreview.init) }, set: { codexPreview = $0?.p })) { p in
            DiffSheet(preview: p.p, title: "~/.codex/config.toml") { approved in
                if approved {
                    do { try HookSetup.applyCodex(p.p); message = L("hooks.written") } catch { message = error.localizedDescription }
                }
                codexPreview = nil
                codexInstalled = HookSetup.codexInstalled
            }
        }
    }

    private var statusText: String {
        switch status {
        case .installed: return L("hooks.installed")
        case .needsUpdate: return L("hooks.needsUpdate")
        case .notInstalled: return L("hooks.notInstalled")
        }
    }

    private func open(_ make: () throws -> HookSetup.Preview) {
        do { preview = try make() } catch { message = L("hooks.invalidJSON") }
    }
}

struct IdentifiedPreview: Identifiable {
    let id = UUID()
    let p: HookSetup.Preview
}

struct DiffSheet: View {
    var preview: HookSetup.Preview
    var title = "~/.claude/settings.json"
    var done: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SwiftUI.Text(title).font(.headline)
            SwiftUI.Text(preview.summary).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(preview.diff.enumerated()), id: \.offset) { _, line in
                        switch line {
                        case .same(let s): SwiftUI.Text("  " + s).foregroundStyle(.secondary)
                        case .added(let s): SwiftUI.Text("+ " + s).foregroundStyle(.green)
                        case .removed(let s): SwiftUI.Text("− " + s).foregroundStyle(.red)
                        }
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 260)
            .background(Color(nsColor: .textBackgroundColor))
            SwiftUI.Text(L("hooks.backupNote")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L("button.cancel")) { done(false) }.keyboardShortcut(.cancelAction)
                Button(L("button.apply")) { done(true) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 460)
    }
}

struct TerminalSettings: View {
    @StateBox private var installed = HookSetup.shellIntegrationInstalled
    @StateBox private var message: String?
    private var model: AppModel { AppModel.shared }

    var body: some View {
        FeatureToggles(features: [.commands, .ports, .docker, .github, .widgets, .terminal])
        Section("GitHub & widgets") {
            LabeledContent(L("ci.repos"), value: AppModel.shared.recentRepos.isEmpty ? "—" : AppModel.shared.recentRepos.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))
            LabeledContent(L("widgets.folder"), value: "~/.config/dylan/widgets")
            SwiftUI.Text(L("widgets.hint")).font(.caption).foregroundStyle(.secondary)
        }
        Section(L("terminal.shell")) {
            LabeledContent("zsh") {
                SwiftUI.Text(installed ? L("terminal.active") : L("terminal.inactive")).foregroundStyle(installed ? .green : .secondary)
            }
            HStack {
                SwiftUI.Text(HookSetup.zshLine).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button(L("button.copy")) {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(HookSetup.zshLine, forType: .string)
                }
            }
            if !installed {
                Button(L("terminal.addToZshrc")) {
                    do { try HookSetup.installShellIntegration(); installed = true; message = L("terminal.added") }
                    catch { message = error.localizedDescription }
                }
            }
            Button(L("terminal.linkCLI")) {
                do { try HookSetup.linkCLI(); message = L("terminal.linked") } catch { message = error.localizedDescription }
            }
            if let message { SwiftUI.Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        Section {
            Stepper(L("terminal.threshold", Int(model.commandThreshold)),
                    value: Binding(get: { model.commandThreshold }, set: { model.commandThreshold = $0 }), in: 3...120, step: 1)
            Picker(L("terminal.showResults"), selection: Binding(get: { model.commandResultsAlways }, set: { model.commandResultsAlways = $0 })) {
                SwiftUI.Text(L("terminal.whenBackground")).tag(false)
                SwiftUI.Text(L("terminal.always")).tag(true)
            }
            .pickerStyle(.segmented)
            LabeledContent(L("terminal.ignore")) {
                SwiftUI.Text(CommandFilter.defaultIgnore.prefix(8).joined(separator: "  ") + "  +\(CommandFilter.defaultIgnore.count - 8)")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        TouchIDSudoCard()
    }
}

/// Settings → Supported features (design D37): search, filter with counts, Developer toggle,
/// groups like the Settings sidebar. Status comes from `FeatureSupport` (what this build ships).
struct FeatureSupportSettings: View {
    enum Filter: Hashable { case all, available, soon, experimental }
    @StateBox private var filter = Filter.all
    @StateBox private var query = ""
    private var model: AppModel { AppModel.shared }
    private let os = ProcessInfo.processInfo.operatingSystemVersion

    private func status(_ f: FeatureSupport) -> FeatureSupport.Status { f.status(macOSMajor: os.majorVersion) }
    private func name(_ f: FeatureSupport) -> String { L10n.string("support.\(f.id)") }
    private func desc(_ f: FeatureSupport) -> String { L10n.string("support.\(f.id).desc") }

    private func matchesQuery(_ f: FeatureSupport) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || (name(f) + " " + desc(f)).lowercased().contains(q)
    }

    private func matchesFilter(_ f: FeatureSupport) -> Bool {
        switch (filter, status(f)) {
        case (.all, _): return true
        case (.available, .available): return true
        case (.soon, .soon), (.soon, .planned): return true
        case (.experimental, .experimental): return true
        default: return false
        }
    }

    /// Search + profile apply to the counts; the filter does not (same as the design).
    private var searched: [FeatureSupport] {
        FeatureSupport.all.filter { matchesQuery($0) && (model.isDeveloper || !$0.isDeveloper) }
    }

    private var hiddenDeveloper: Int {
        model.isDeveloper || filter == .experimental ? 0 : FeatureSupport.all.filter { $0.isDeveloper && matchesQuery($0) }.count
    }

    var body: some View {
        let visible = FeatureSupport.all.filter { model.isDeveloper || !$0.isDeveloper }
        Section {
            HStack {
                // The page banner already carries the title (D50).
                SwiftUI.Text(L("support.version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
                               "\(os.majorVersion).\(os.minorVersion)"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                SwiftUI.Text(L("support.devToggle")).font(.callout)
                Toggle(L("support.devToggle"), isOn: Binding(get: { model.isDeveloper },
                                                             set: { model.features.profile = $0 ? .developer : .general }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
            TextField("", text: $query, prompt: SwiftUI.Text(L("support.search")))
                .textFieldStyle(.roundedBorder).labelsHidden()
            Picker("", selection: $filter) {
                SwiftUI.Text("\(L("support.filter.all")) \(searched.count)").tag(Filter.all)
                SwiftUI.Text("\(L("support.filter.available")) \(searched.filter { status($0) == .available }.count)").tag(Filter.available)
                SwiftUI.Text("\(L("support.filter.soon")) \(searched.filter { [.soon, .planned].contains(status($0)) }.count)").tag(Filter.soon)
                SwiftUI.Text("\(L("support.filter.experimental")) \(searched.filter { status($0) == .experimental }.count)").tag(Filter.experimental)
            }
            .pickerStyle(.segmented).labelsHidden()
            SwiftUI.Text(L("support.summary", visible.filter { status($0) == .available }.count,
                           visible.filter { [.soon, .planned].contains(status($0)) }.count,
                           visible.filter { status($0) == .experimental }.count))
                .font(.caption).foregroundStyle(.secondary)
        }

        let groups = FeatureSupport.Group.allCases.compactMap { g -> (FeatureSupport.Group, [FeatureSupport])? in
            let items = searched.filter { $0.group == g && matchesFilter($0) }
            return items.isEmpty ? nil : (g, items)
        }
        ForEach(groups, id: \.0) { g, items in
            Section {
                ForEach(items) { row($0) }
            } header: {
                HStack {
                    SwiftUI.Text(groupTitle(g))
                    Spacer()
                    SwiftUI.Text(L("support.groupCount", items.filter { status($0) == .available }.count, items.count))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        if hiddenDeveloper > 0 {
            Section {
                HStack {
                    Image(systemName: "terminal").frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        SwiftUI.Text(L("support.devHidden", hiddenDeveloper))
                        SwiftUI.Text(L("support.devHiddenBody")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("support.useDeveloper")) { model.features.profile = .developer }
                }
            }
        }
        if groups.isEmpty && hiddenDeveloper == 0 {
            Section { SwiftUI.Text(L("support.empty", query)).foregroundStyle(.secondary) }
        }
        Section { SwiftUI.Text(L("support.footer")).font(.caption).foregroundStyle(.secondary) }
    }

    private func groupTitle(_ g: FeatureSupport.Group) -> String {
        switch g {
        case .notch: return L("support.group.notch")
        case .media: return L("support.group.media")
        case .calendar: return L("support.group.calendar")
        case .devices: return L("support.group.devices")
        case .communication: return L("support.group.communication")
        case .files: return L("support.group.files")
        case .utilities: return L("support.group.utilities")
        case .security: return L("support.group.security")
        case .developer: return L("support.group.developer")
        }
    }

    private func row(_ f: FeatureSupport) -> some View {
        let st = status(f)
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                SwiftUI.Text(name(f)).foregroundStyle(st == .available ? .primary : .secondary)
                SwiftUI.Text(desc(f)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if f.hasRequirement {
                SwiftUI.Text(L10n.string("support.\(f.id).req")).font(.caption).foregroundStyle(.secondary)
            }
            badge(st)
        }
        .accessibilityElement(children: .combine)
    }

    /// Colours from the design: green available, grey next/planned, amber experimental.
    private func badge(_ st: FeatureSupport.Status) -> some View {
        let (text, fg, bg): (String, Color, Color) = switch st {
        case .available: (L("support.status.available"), Color(red: 0.10, green: 0.50, blue: 0.22), Color(red: 0.89, green: 0.96, blue: 0.91))
        case .soon: (L("support.status.soon"), Color(white: 0.23), Color(red: 0.93, green: 0.92, blue: 0.91))
        case .planned: (L("support.status.planned"), Color(white: 0.43), Color(red: 0.95, green: 0.95, blue: 0.93))
        case .experimental: (L("support.status.experimental"), Color(red: 0.48, green: 0.35, blue: 0), Color(red: 1, green: 0.96, blue: 0.8))
        case .unsupported: (L("support.status.unsupported"), Color(white: 0.43), Color(red: 0.95, green: 0.95, blue: 0.93))
        }
        return SwiftUI.Text(text).font(.caption.weight(.semibold)).foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(bg))
    }
}

/// Who made Dylan: Settings → About and the standard About panel (from the menu bar).
enum About {
    static let author = "Egie Ramdan"
    static let profile = URL(string: "https://github.com/ramdanegie")!
    static let repository = URL(string: "https://github.com/ramdanegie/dylan")!

    static func showPanel() {
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor, .paragraphStyle: center]
        let credits = NSMutableAttributedString(string: L("about.madeByName", author) + "\n", attributes: base)
        credits.append(NSAttributedString(string: "github.com/ramdanegie", attributes: base.merging([.link: profile]) { $1 }))
        credits.append(NSAttributedString(string: "  ·  ", attributes: base))
        credits.append(NSAttributedString(string: "Source code", attributes: base.merging([.link: repository]) { $1 }))
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}

struct AboutSettings: View {
    private var updates: UpdateService { UpdateService.shared }

    var body: some View {
        Section {
            LabeledContent("Dylan", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
            SwiftUI.Text(L("about.body")).foregroundStyle(.secondary)
            LabeledContent(L("about.madeBy")) { SwiftUI.Text(About.author).fontWeight(.medium) }
            HStack(spacing: 16) {
                Link(destination: About.profile) { Label("github.com/ramdanegie", systemImage: "person.crop.circle") }
                Link(destination: About.repository) { Label("Source code", systemImage: "chevron.left.forwardslash.chevron.right") }
            }
        }
        Section(L("update.title")) {
            Toggle(isOn: Binding(get: { updates.autoCheck }, set: { updates.autoCheck = $0 })) {
                SwiftUI.Text(L("update.auto"))
                SwiftUI.Text(L("update.autoHint")).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(L("update.checkNow")) { updates.check(manual: true) }.disabled(updates.state == .checking)
                Button(L("update.whatsNew")) { WhatsNewWindow.show() }.disabled(updates.whatsNew() == nil)
                Spacer()
                SwiftUI.Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        switch updates.state {
        case .idle: return ""
        case .checking: return L("update.checking")
        case .upToDate: return L("update.upToDate", updates.current)
        case .available(let r): return L("update.available", r.version?.description ?? r.tag)
        case .failed: return L("update.failed")
        }
    }
}

enum App {
    static func relaunch() {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else { NSApp.terminate(nil); return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait until this process is gone (quitting can wait for a recording to finish), then open again.
        p.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", path, "\(getpid())"]
        try? p.run()
        NSApp.terminate(nil)
    }
}

/// FR-50–55, 116–119 (experimental): the warning comes first, then enrollment with the verified password.
/// Anything that lets Face Unlock open more easily asks for Touch ID first; turning things off never does.
struct FaceUnlockSettings: View {
    private var face: FaceUnlockProvider { FaceUnlockProvider.shared }
    @StateBox private var newPassword: String?
    @StateBox private var passwordError: String?

    /// Off is free; on goes through Touch ID.
    private func guarded(_ get: @escaping @MainActor @Sendable () -> Bool, _ set: @escaping @MainActor @Sendable (Bool) -> Void) -> Binding<Bool> {
        Binding(get: get, set: { on in on ? face.authorize { set(true) } : set(false) })
    }

    var body: some View {
        Section {
            if face.enrolled {
                Toggle(isOn: guarded({ face.vault.settings.enabled }, { FaceUnlockProvider.shared.vault.settings.enabled = $0; FaceUnlockProvider.shared.save() })) {
                    SwiftUI.Text(L("faceUnlock.enable"))
                    SwiftUI.Text(L("faceUnlock.enableHint")).font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent(L("faceUnlock.maxLockedLabel")) {
                    Stepper(L("faceUnlock.minutes", face.vault.settings.maxLockedMinutes),
                            value: Binding(get: { face.vault.settings.maxLockedMinutes }, set: { v in
                                let apply: @MainActor @Sendable () -> Void = { FaceUnlockProvider.shared.vault.settings.maxLockedMinutes = v; FaceUnlockProvider.shared.save() }
                                v > face.vault.settings.maxLockedMinutes ? face.authorize(apply) : apply()
                            }), in: 5...240, step: 5)
                }
                // Why it would not try on the next wake (the most common: no Accessibility, no password unlock yet).
                if let issue = face.readinessIssue {
                    HStack {
                        Label(L("faceUnlock.denial.\(issue.rawValue)"), systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                        Spacer()
                        if issue == .noAccessibility {
                            Button(L("faceUnlock.openAccessibility")) {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                            }
                        }
                    }
                } else {
                    Label(L("faceUnlock.readyNow"), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
            } else {
                SwiftUI.Text(L("faceUnlock.warning")).font(.caption).foregroundStyle(.orange)
                Button(L("faceUnlock.enroll")) { FaceEnrollWindow.show() }
            }
            if let s = face.status { SwiftUI.Text(s).font(.caption).foregroundStyle(.secondary) }
        } header: {
            HStack { SwiftUI.Text(L("faceUnlock.title")); Badge() }
        }
        if face.enrolled {
            identities
            lockScreen
            lab
            Section {
                if let pw = newPassword {
                    HStack {
                        SecureField(L("faceUnlock.passwordField"), text: Binding(get: { pw }, set: { newPassword = $0 })).textFieldStyle(.roundedBorder)
                            .onSubmit(savePassword)
                        Button(L("button.cancel")) { newPassword = nil; passwordError = nil }
                        Button(L("faceUnlock.save")) { savePassword() }.disabled(pw.isEmpty)
                    }
                    if let passwordError { SwiftUI.Text(passwordError).font(.caption).foregroundStyle(.red) }
                }
                HStack {
                    if newPassword == nil {
                        Button(L("faceUnlock.changePassword")) { face.authorize { FaceUnlockSettings.beginPassword() } }
                    }
                    Spacer()
                    Button(L("faceUnlock.delete"), role: .destructive) { face.deleteEnrollment() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: FaceUnlockSettings.passwordRequest)) { _ in newPassword = ""; passwordError = nil }
        }
        if !face.vault.log.events.isEmpty {
            Section {
                Button(L("faceUnlock.copyLog")) { face.copyLog() }
                ForEach(Array(face.vault.log.events.prefix(10).enumerated()), id: \.offset) { _, e in
                    HStack {
                        SwiftUI.Text(e.at.formatted(date: .abbreviated, time: .shortened))
                        SwiftUI.Text(L("faceUnlock.result.\(e.result.rawValue)"))
                        if let r = e.reason { SwiftUI.Text(FaceUnlockProvider.reasonText(r)).foregroundStyle(.secondary) }
                        Spacer()
                        if let i = e.identity { SwiftUI.Text(String(format: "%.2f", i)).monospacedDigit().foregroundStyle(.secondary) }
                    }
                    .font(.caption)
                    if let t = e.trace {
                        SwiftUI.Text(FaceUnlockProvider.traceText(t)).font(.caption2).monospacedDigit().foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            } header: { SwiftUI.Text(L("faceUnlock.log")) }
        }
    }
}

extension FaceUnlockSettings {
    /// Touch ID answered on another task; the field opens through a notification so no view state is captured.
    static let passwordRequest = Notification.Name("dylan.faceUnlock.passwordRequest")
    static func beginPassword() { NotificationCenter.default.post(name: passwordRequest, object: nil) }

    private func savePassword() {
        guard let pw = newPassword, !pw.isEmpty else { return }
        passwordError = face.changePassword(pw)
        if passwordError == nil { newPassword = nil }
    }

    /// Glance's identities: plain, glasses, a mask, dim light; each can be off without being deleted.
    private var identities: some View {
        Section {
            ForEach(face.vault.identities) { i in
                HStack {
                    Image(systemName: "faceid").foregroundStyle(.secondary)
                    SwiftUI.Text(FaceUnlockProvider.displayName(i))
                    Spacer()
                    Toggle("", isOn: guarded({ i.enabled }, { FaceUnlockProvider.shared.setIdentity(i.id, enabled: $0) })).labelsHidden()
                    // The last one goes only with "Delete face data & password" below.
                    Button(role: .destructive) { face.deleteIdentity(i.id) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .disabled(face.vault.identities.count < 2)
                        .help(L("faceUnlock.identity.delete"))
                        .accessibilityLabel(L("faceUnlock.identity.delete"))
                }
            }
            HStack {
                SwiftUI.Text(L("faceUnlock.identitiesHint")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("faceUnlock.addIdentity")) { face.authorize { FaceEnrollWindow.show(adding: true) } }
                    .disabled(face.vault.identities.count >= FaceVault.maxIdentities)
            }
        } header: { SwiftUI.Text(L("faceUnlock.identities")) }
    }

    private var lockScreen: some View {
        Section {
            Toggle(isOn: Binding(get: { face.vault.settings.lockScreenIsland }, set: { face.vault.settings.lockScreenIsland = $0; face.save() })) {
                SwiftUI.Text(L("faceUnlock.island"))
                SwiftUI.Text(L("faceUnlock.islandHint")).font(.caption).foregroundStyle(.secondary)
            }
            Toggle(L("faceUnlock.speak"), isOn: Binding(get: { face.vault.settings.speak }, set: { face.vault.settings.speak = $0; face.save() }))
            Toggle(isOn: guarded({ face.vault.settings.spaceRetry }, { on in
                if on { FaceUnlockProvider.requestInputMonitoring() }
                FaceUnlockProvider.shared.vault.settings.spaceRetry = on
                FaceUnlockProvider.shared.save()
            })) {
                SwiftUI.Text(L("faceUnlock.spaceRetry"))
                SwiftUI.Text(L("faceUnlock.spaceRetryHint")).font(.caption).foregroundStyle(.secondary)
            }
            if face.vault.settings.spaceRetry, !FaceUnlockProvider.inputMonitoringAllowed {
                HStack {
                    Label(L("faceUnlock.needsInputMonitoring"), systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button(L("faceUnlock.openInputMonitoring")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                    }
                }
            }
        } header: { SwiftUI.Text(L("faceUnlock.lockScreen")) }
    }

    /// Glance's Face Lab: the camera for 10 s with the live score per identity; nothing unlocks, nothing is stored.
    private var lab: some View {
        Section {
            HStack {
                SwiftUI.Text(L("faceUnlock.labHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                if face.labCamera != nil {
                    Button(L("faceUnlock.labStop")) { face.stopLab() }
                } else {
                    // The live score helps tune a photo or a mask too, so it is behind Touch ID like the rest.
                    Button(L("faceUnlock.labStart")) { face.authorize { FaceUnlockProvider.shared.startLab() } }
                    Button(L("faceUnlock.practice")) { face.authorize { FaceUnlockProvider.shared.startPractice() } }
                        .disabled(face.practice?.step != nil || !face.vault.canMatch)
                }
            }
            if let p = face.practice {
                if let step = p.step {
                    Label(L("faceUnlock.scan.step", p.index, p.count) + ": " + step, systemImage: "faceid").font(.callout.bold())
                } else if let ok = p.passed {
                    Label(ok ? L("faceUnlock.practicePassed") : L("faceUnlock.practiceFailed", FaceUnlockProvider.reasonText(p.reason)),
                          systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(ok ? .green : .red)
                    if let t = p.trace { SwiftUI.Text(FaceUnlockProvider.traceText(t)).font(.caption).monospacedDigit().foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }
            if let r = face.lab {
                let fmt: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(2)).locale(L10n.locale)) }
                ForEach(face.vault.identities) { i in
                    let score = r.scores[i.id]
                    LabeledContent(FaceUnlockProvider.displayName(i)) {
                        SwiftUI.Text(score.map(fmt) ?? "—").monospacedDigit()
                            .foregroundStyle((score ?? 0) >= 0.66 ? .green : .secondary)
                    }
                }
                LabeledContent(L("faceUnlock.labFaces"), value: "\(r.faces)")
                LabeledContent(L("faceUnlock.labHead"), value: "\(Int(r.yaw.rounded()))° · \(Int(r.pitch.rounded()))°")
                LabeledContent(L("faceUnlock.labEyes"), value: fmt(r.eyesOpen))
                LabeledContent(L("faceUnlock.labPeaks")) {
                    SwiftUI.Text(FaceUnlockProvider.traceText(r.peaks)).monospacedDigit()
                }
                if r.device { Label(L("faceUnlock.labDevice"), systemImage: "iphone.gen3").font(.caption).foregroundStyle(.orange) }
            }
        } header: { SwiftUI.Text(L("faceUnlock.lab")) }
        .font(.callout)
    }
}
