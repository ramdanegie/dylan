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
    case general, appearance, liveActivity, media, devices, agents, terminal, about
    var id: String { rawValue }
    var isDeveloper: Bool { self == .agents || self == .terminal }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .liveActivity: return "bell.badge"
        case .media: return "music.note"
        case .devices: return "battery.100percent.bolt"
        case .agents: return "sparkle"
        case .terminal: return "terminal"
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
        case .media: FeatureToggles(features: [.media, .meeting, .timer])
        case .devices: FeatureToggles(features: [.battery, .bluetooth, .privacy])
        case .agents: AgentSettings()
        case .terminal: TerminalSettings()
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
    private var model: AppModel { AppModel.shared }
    var body: some View {
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

struct AgentSettings: View {
    @StateBox private var preview: HookSetup.Preview?
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
    var done: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SwiftUI.Text("~/.claude/settings.json").font(.headline)
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
