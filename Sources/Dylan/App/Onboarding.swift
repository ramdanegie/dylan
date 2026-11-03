import AppKit
import DylanCore
import SwiftUI

/// Onboarding (PRD §F14, design D1): language → profile → features → permissions, plus 2 Developer steps.
/// Every step can be skipped.
enum OnboardingWindow {
    nonisolated(unsafe) private static var window: NSWindow?

    static func show() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: OnboardingView { OnboardingWindow.close() })
        w.center()
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    static func close() {
        AppModel.shared.onboardingDone = true
        window?.close()
        window = nil
    }
}

struct OnboardingView: View {
    var finish: () -> Void
    @StateBox private var step = 0
    @StateBox private var chosen: Set<Feature> = [.media, .meeting, .battery, .timer, .privacy]
    @StateBox private var hookPreview: HookSetup.Preview?
    @StateBox private var note: String?
    @StateBox private var askRelaunch = false
    private var model: AppModel { AppModel.shared }

    private var steps: Int { model.isDeveloper ? 6 : 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                switch step {
                case 0: welcome
                case 1: profile
                case 2: features
                case 3: permissions
                case 4: hooks
                default: shell
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let note { SwiftUI.Text(note).font(.caption).foregroundStyle(.secondary) }
            HStack {
                SwiftUI.Text(L("onboarding.step", step + 1, steps)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if step > 0 { Button(L("button.skip")) { advance() } }
                Button(step == 0 ? L("button.start") : (step == steps - 1 ? L("button.done") : L("button.next"))) { primary() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 620, height: 460)
        .alert(L("language.relaunchTitle"), isPresented: $askRelaunch) {
            Button(L("button.later"), role: .cancel) {}
            Button(L("button.relaunch")) { App.relaunch() }
        } message: { SwiftUI.Text(L("language.relaunchBody")) }
    }

    private func advance() {
        note = nil
        if step >= steps - 1 { finish() } else { step += 1 }
    }

    private func primary() {
        switch step {
        case 2:
            for f in [Feature.media, .meeting, .battery, .bluetooth, .timer, .privacy] { model.features.toggles[f] = chosen.contains(f) }
        case 4:
            if let p = hookPreview {
                do { try HookSetup.apply(p); note = L("hooks.written") } catch { note = error.localizedDescription; return }
            }
        case 5:
            do { try HookSetup.installShellIntegration() } catch { note = error.localizedDescription; return }
        default: break
        }
        advance()
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Picker(selection: Binding(get: { model.language }, set: { model.language = $0; askRelaunch = true })) {
                    SwiftUI.Text(L("language.followSystem")).tag(LanguageChoice.system)
                    SwiftUI.Text("Bahasa Indonesia").tag(LanguageChoice.indonesian)
                    SwiftUI.Text("English").tag(LanguageChoice.english)
                } label: { Image(systemName: "globe") }
                .frame(width: 200)
            }
            Capsule().fill(.black).frame(width: 220, height: 34)
                .overlay(HStack { Image(systemName: "music.note"); Spacer(); Equalizer(playing: true, color: .orange) }
                    .foregroundStyle(.white).padding(.horizontal, 14))
                .frame(maxWidth: .infinity)
            SwiftUI.Text(L("onboarding.welcomeTitle")).font(.system(size: 26, weight: .bold))
            SwiftUI.Text(L("onboarding.welcomeBody")).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                SwiftUI.Text("· " + L("onboarding.point1"))
                SwiftUI.Text("· " + L("onboarding.point2"))
                SwiftUI.Text("· " + L("onboarding.point3"))
            }
            .foregroundStyle(.secondary)
        }
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 14) {
            SwiftUI.Text(L("onboarding.profileTitle")).font(.system(size: 22, weight: .bold))
            HStack(spacing: 14) {
                profileCard(.general, symbol: "music.note", title: L("profile.general"), body: L("onboarding.profileGeneral"))
                profileCard(.developer, symbol: "terminal", title: L("profile.developer"), body: L("onboarding.profileDeveloper"))
            }
            SwiftUI.Text(L("onboarding.profileHint")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func profileCard(_ p: Profile, symbol: String, title: String, body: String) -> some View {
        let selected = model.features.profile == p
        return Button { model.features.profile = p } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.title2)
                SwiftUI.Text(title).font(.headline)
                SwiftUI.Text(body).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 12) {
            SwiftUI.Text(L("onboarding.featuresTitle")).font(.system(size: 22, weight: .bold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach([Feature.media, .meeting, .battery, .bluetooth, .timer, .privacy], id: \.self) { f in
                    Toggle(isOn: Binding(get: { chosen.contains(f) }, set: { if $0 { chosen.insert(f) } else { chosen.remove(f) } })) {
                        VStack(alignment: .leading) {
                            SwiftUI.Text(L("feature.\(f.rawValue)")).font(.headline)
                            SwiftUI.Text(L("feature.\(f.rawValue).hint")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
                }
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SwiftUI.Text(L("onboarding.permissionsTitle")).font(.system(size: 22, weight: .bold))
            SwiftUI.Text(L("onboarding.permissionsHint")).foregroundStyle(.secondary)
            if chosen.contains(.meeting) {
                permissionRow(L("permission.calendar"), L("permission.calendarWhy"), granted: CalendarProvider.shared.status == .fullAccess) {
                    CalendarProvider.shared.start(requestAccess: true)
                }
            }
            if chosen.contains(.media) {
                permissionRow(L("permission.automation"), L("permission.automationWhy"), granted: false) {
                    MediaProvider.shared.start()
                    note = L("permission.automationNote")
                }
            }
            if chosen.contains(.bluetooth) {
                permissionRow(L("permission.bluetooth"), L("permission.bluetoothWhy"), granted: false) { BluetoothProvider.shared.start() }
            }
        }
    }

    private func permissionRow(_ title: String, _ why: String, granted: Bool, _ ask: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) {
                SwiftUI.Text(title).font(.headline)
                SwiftUI.Text(why).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted { Label(L("permission.allowed"), systemImage: "checkmark").foregroundStyle(.green) }
            else { Button(L("button.allow"), action: ask) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    private var hooks: some View {
        VStack(alignment: .leading, spacing: 10) {
            SwiftUI.Text(L("onboarding.devOnly")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            SwiftUI.Text(L("onboarding.hooksTitle")).font(.system(size: 22, weight: .bold))
            SwiftUI.Text(L("onboarding.hooksBody")).foregroundStyle(.secondary)
            if let p = hookPreview {
                SwiftUI.Text(p.summary).font(.caption)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(p.diff.enumerated()).filter { if case .same = $0.element { return false }; return true }, id: \.offset) { _, l in
                            if case .added(let s) = l { SwiftUI.Text("+ " + s).foregroundStyle(.green) }
                            if case .removed(let s) = l { SwiftUI.Text("− " + s).foregroundStyle(.red) }
                        }
                    }
                    .font(.system(size: 10.5, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 150).background(Color(nsColor: .textBackgroundColor))
            }
        }
        .onAppear {
            do { hookPreview = HookSetup.status() == .installed ? nil : try HookSetup.previewInstall() }
            catch { note = L("hooks.invalidJSON") }
            if HookSetup.status() == .installed { note = L("hooks.installed") }
        }
    }

    private var shell: some View {
        VStack(alignment: .leading, spacing: 10) {
            SwiftUI.Text(L("onboarding.devOnly")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            SwiftUI.Text(L("onboarding.shellTitle")).font(.system(size: 22, weight: .bold))
            SwiftUI.Text(L("onboarding.shellBody")).foregroundStyle(.secondary)
            HStack {
                SwiftUI.Text(HookSetup.zshLine).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button(L("button.copy")) {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(HookSetup.zshLine, forType: .string)
                }
            }
            .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
            SwiftUI.Text(L("onboarding.shellPrimary")).font(.caption).foregroundStyle(.secondary)
        }
    }
}
