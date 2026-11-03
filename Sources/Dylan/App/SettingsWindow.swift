import AppKit
import DylanCore
import ServiceManagement
import SwiftUI

/// Settings (PRD §F14, design D16/D36). Developer sections only appear in the Developer profile.
enum SettingsWindow {
    nonisolated(unsafe) private static var window: NSWindow?

    static func show(section: SettingsSection = .general) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = L("settings.title")
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
    case general, appearance, liveActivity, media, discord, devices, utilities, clipboard, agents, terminal, features, about
    var id: String { rawValue }
    var isDeveloper: Bool { self == .agents || self == .terminal }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .liveActivity: return "bell.badge"
        case .media: return "music.note"
        case .discord: return "headphones"
        case .devices: return "battery.100percent.bolt"
        case .utilities: return "wrench.and.screwdriver"
        case .clipboard: return "doc.on.clipboard"
        case .agents: return "sparkle"
        case .terminal: return "terminal"
        case .features: return "checklist"
        case .about: return "info.circle"
        }
    }
    var title: String { L("settings.section.\(rawValue)") }
}

struct SettingsView: View {
    @StateBox var selection: SettingsSection
    private var model: AppModel { AppModel.shared }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SettingsSection.allCases.filter { !$0.isDeveloper }) { s in
                    Label(s.title, systemImage: s.symbol).tag(s)
                }
                if model.isDeveloper {
                    Section(L("settings.developer")) {
                        ForEach(SettingsSection.allCases.filter(\.isDeveloper)) { s in Label(s.title, systemImage: s.symbol).tag(s) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Form { detail }.formStyle(.grouped).navigationTitle(selection.title)
        }
        .frame(minWidth: 700, minHeight: 480)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .general: GeneralSettings()
        case .appearance: AppearanceSettings()
        case .liveActivity: LiveActivitySettings()
        case .media:
            FeatureToggles(features: [.media, .lyrics, .meeting, .reminders, .timer])
            QuickPlaySettings()
        case .devices:
            FeatureToggles(features: [.battery, .bluetooth, .privacy, .keepAwake, .hud])
            KeepAwakeSettings()
        case .utilities: UtilitySettings()
        case .discord: DiscordSettings()
        case .clipboard: ClipboardSettings()
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
            if #available(macOS 26, *) {
                Toggle(L("theme.glass"), isOn: Binding(get: { model.glassPill }, set: { model.glassPill = $0 }))
            } else {
                LabeledContent(L("theme.glass"), value: L("support.status.unsupported"))
            }
            SwiftUI.Text(L("theme.blackNotch")).font(.caption).foregroundStyle(.secondary)
        }
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
                    .multilineTextAlignment(.trailing)
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
                TextField("", text: Binding(get: { model.discordMuteKey }, set: { model.discordMuteKey = $0 })).multilineTextAlignment(.trailing)
            }
            LabeledContent(L("discord.toggleDeafen")) {
                TextField("", text: Binding(get: { model.discordDeafKey }, set: { model.discordDeafKey = $0 })).multilineTextAlignment(.trailing)
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
            TextField(L("weather.city"), text: Binding(get: { model.weatherCity }, set: { model.weatherCity = $0 }))
                .onSubmit { WeatherProvider.shared.cityChanged() }
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
        FeatureToggles(features: [.commands, .ports, .docker, .github, .widgets])
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
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    SwiftUI.Text(L("settings.section.features")).font(.title3.weight(.semibold))
                    SwiftUI.Text(L("support.version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
                                   "\(os.majorVersion).\(os.minorVersion)"))
                        .font(.caption).foregroundStyle(.secondary)
                }
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

struct AboutSettings: View {
    var body: some View {
        Section {
            LabeledContent("Dylan", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
            SwiftUI.Text(L("about.body")).foregroundStyle(.secondary)
            Link("github.com/ramdanegie/dylan", destination: URL(string: "https://github.com/ramdanegie/dylan")!)
        }
    }
}

enum App {
    static func relaunch() {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else { NSApp.terminate(nil); return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }
}
