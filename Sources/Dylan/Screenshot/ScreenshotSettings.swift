import AppKit
import DylanCore
import SwiftUI

/// Settings → Screenshot (design D43).
struct ScreenshotSettings: View {
    private var d: UserDefaults { AppModel.store }
    @StateBox private var permitted = CGPreflightScreenCaptureAccess()
    @StateBox private var refresh = 0

    private func bool(_ key: String, _ def: Bool) -> Binding<Bool> {
        Binding(get: { _ = refresh; return d.object(forKey: key) as? Bool ?? def }, set: { d.set($0, forKey: key); refresh += 1 })
    }

    private func string(_ key: String, _ def: String) -> Binding<String> {
        Binding(get: { _ = refresh; return d.string(forKey: key) ?? def }, set: { d.set($0, forKey: key); refresh += 1 })
    }

    var body: some View {
        FeatureToggles(features: [.screenshot])
        Section {
            HStack {
                SwiftUI.Text(L("shot.permission"))
                Spacer()
                SwiftUI.Text(permitted ? L("shot.permitted") : L("shot.notPermitted")).foregroundStyle(permitted ? .green : .orange)
                if !permitted {
                    Button(L("shot.allow")) {
                        _ = CGRequestScreenCaptureAccess()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")!)
                    }
                }
            }
        }
        Section(L("shot.shortcuts")) {
            ForEach([("shot.captureArea", "⌥⇧1"), ("shot.captureWindow", "⌥⇧2"), ("shot.captureScreen", "⌥⇧3"), ("shot.captureScroll", "⌥⇧4"),
                     ("shot.captureText", "⌥⇧T"), ("shot.openLast", "⌥⇧E")], id: \.0) { k, v in
                LabeledContent(L(k)) { SwiftUI.Text(v).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) }
            }
            Toggle(L("shot.takeOver"), isOn: Binding(get: { _ = refresh; return d.bool(forKey: "shot.takeOver") },
                                                    set: { d.set($0, forKey: "shot.takeOver"); Hotkeys.setTakeOver($0 && AppModel.shared.features.isEnabled(.screenshot)); refresh += 1 }))
            SwiftUI.Text(L("shot.takeOverHint")).font(.caption).foregroundStyle(.secondary)
            if d.bool(forKey: "shot.takeOver") {
                Button(L("shot.openKeyboardShortcuts")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                }
            }
        }
        Section(L("shot.afterCapture")) {
            Picker(L("shot.afterCapture"), selection: string("shot.after", "editor")) {
                SwiftUI.Text(L("shot.after.editor")).tag("editor")
                SwiftUI.Text(L("shot.after.notch")).tag("notch")
                SwiftUI.Text(L("shot.after.studio")).tag("studio")
                SwiftUI.Text(L("shot.after.saveOnly")).tag("saveOnly")
            }
            .pickerStyle(.radioGroup)
            Toggle(L("shot.alsoSave"), isOn: bool("shot.saveFile", false))
            LabeledContent(L("shot.folder")) {
                HStack {
                    SwiftUI.Text(ShotPrefs.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).foregroundStyle(.secondary).lineLimit(1)
                    Button(L("shot.choose")) {
                        let p = NSOpenPanel()
                        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
                        if p.runModal() == .OK, let u = p.url { d.set(u.path, forKey: "shot.folder"); refresh += 1 }
                    }
                }
            }
            Picker(L("shot.format"), selection: string("shot.format", "png")) {
                SwiftUI.Text("PNG").tag("png"); SwiftUI.Text("JPG").tag("jpg")
                if ScreenshotService.canWriteWebP { SwiftUI.Text("WebP").tag("webp") }
            }
            .pickerStyle(.segmented)
            LabeledContent(L("shot.fileName")) { SwiftUI.Text(CaptureStore.fileName(Date(), ext: ShotPrefs.format)).foregroundStyle(.secondary) }
        }
        Section(L("shot.whileCapturing")) {
            Toggle(L("shot.hideIcons"), isOn: bool("shot.hideIcons", true))
            Toggle(L("shot.loupe"), isOn: bool("shot.loupe", true))
            Toggle(L("shot.windowShadow"), isOn: bool("shot.windowShadow", true))
            Picker(L("shot.resolution"), selection: bool("shot.retina", true)) {
                SwiftUI.Text("1×").tag(false); SwiftUI.Text("Retina").tag(true)
            }
            .pickerStyle(.segmented)
        }
        Section(L("shot.beautifyHistory")) {
            Picker(L("shot.defaultBackground"), selection: Binding(get: { _ = refresh; return ShotPrefs.studioBackground },
                                                                   set: { d.set($0, forKey: "shot.bg"); refresh += 1 })) {
                ForEach(Array(Beautify.backgrounds.enumerated()), id: \.offset) { i, b in SwiftUI.Text(b.name).tag(i) }
            }
            Toggle(L("shot.autoBeautify"), isOn: bool("shot.autoBeautify", false))
            Toggle(L("shot.autoBlur"), isOn: bool("shot.autoBlur", false))
            Picker(L("shot.keepHistory"), selection: Binding(get: { _ = refresh; return ShotPrefs.retentionDays },
                                                             set: { d.set($0, forKey: "shot.retention"); ScreenshotService.shared.pruneHistory(); refresh += 1 })) {
                SwiftUI.Text(L("shot.days", 7)).tag(7); SwiftUI.Text(L("shot.days", 30)).tag(30); SwiftUI.Text(L("shot.days", 90)).tag(90)
                SwiftUI.Text(L("shot.forever")).tag(0)
            }
            HStack {
                let items = ScreenshotService.shared.history
                let bytes = items.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
                let s = CaptureStore.summary(count: items.count, bytes: bytes)
                SwiftUI.Text(L("shot.historySummary", s.count, s.megabytes)).foregroundStyle(.secondary)
                Spacer()
                Button(L("shot.history")) { CaptureHistoryWindow.show() }
                Button(L("shot.clearHistory"), role: .destructive) { ScreenshotService.shared.clearHistory(); refresh += 1 }
            }
        }
        .onAppear { permitted = CGPreflightScreenCaptureAccess() }
    }
}
