import AppKit
import DylanCore
import SwiftUI

/// Update check against GitHub Releases, and What's New from the CHANGELOG bundled in the app.
/// Network only when the user turns on daily checks or presses "Check now" (PRD: all network access is opt-in).
@Observable
final class UpdateService {
    static let shared = UpdateService()
    static let api = URL(string: "https://api.github.com/repos/ramdanegie/dylan/releases?per_page=20")!
    static let releasesPage = URL(string: "https://github.com/ramdanegie/dylan/releases")!
    /// Every Dylan release so far is a pre-release (test builds), so those count as updates.
    static let includePrerelease = true

    enum State: Equatable { case idle, checking, upToDate, available(ReleaseInfo), failed }
    var state: State = .idle

    private var d: UserDefaults { AppModel.store }
    @ObservationIgnored private var timer: Timer?

    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    var autoCheck: Bool {
        get { d.bool(forKey: "update.auto") }
        set { d.set(newValue, forKey: "update.auto"); if newValue { checkIfDue() } }
    }

    func launched() {
        showWhatsNewIfUpdated()
        checkIfDue()
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { _ in MainActor.assumeIsolated { UpdateService.shared.checkIfDue() } }
        t.tolerance = 600
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func checkIfDue() {
        guard autoCheck, Updates.isDue(lastCheck: d.object(forKey: "update.lastCheck") as? Date, now: Date()) else { return }
        check(manual: false)
    }

    func check(manual: Bool) {
        guard state != .checking else { return }
        state = .checking
        var req = URLRequest(url: Self.api, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Dylan/\(current)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { @Sendable data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let releases = ok ? data.flatMap { try? JSONDecoder().decode([ReleaseInfo].self, from: $0) } : nil
            Task { @MainActor in UpdateService.shared.finished(releases, manual: manual) }
        }.resume()
    }

    private func finished(_ releases: [ReleaseInfo]?, manual: Bool) {
        guard let releases else {
            state = .failed
            if manual { UpdateWindow.show() }
            return
        }
        d.set(Date(), forKey: "update.lastCheck")
        // "Check now" ignores a skipped version; the daily check respects it.
        let skipped = manual ? nil : d.string(forKey: "update.skip")
        if let r = Updates.newest(releases, current: current, skipped: skipped, includePrerelease: Self.includePrerelease) {
            state = .available(r)
            if manual { UpdateWindow.show() } else { announce(r) }
        } else {
            state = .upToDate
            if manual { UpdateWindow.show() }
        }
    }

    /// Daily check found one: a short notch notice with "View".
    private func announce(_ r: ReleaseInfo) {
        let now = Date(), v = r.version?.description ?? r.tag
        AppModel.shared.center.post(Activity(id: "update", kind: .notify, priority: .p2, state: .info, symbol: "arrow.down.circle",
                                             label: "Dylan", value: v, detail: L("update.available", v), url: "update:", startedAt: now), now: now)
        AppModel.shared.scheduleTick()
    }

    func skip(_ r: ReleaseInfo) {
        d.set(r.version?.description ?? r.tag, forKey: "update.skip")
        state = .idle
    }

    // MARK: What's New

    func showWhatsNewIfUpdated() {
        let last = d.string(forKey: "update.lastSeenVersion")
        d.set(current, forKey: "update.lastSeenVersion")
        if Changelog.shouldShowWhatsNew(lastSeen: last, current: current), whatsNew() != nil { WhatsNewWindow.show() }
    }

    /// This version's section of the bundled CHANGELOG, in the UI language.
    func whatsNew() -> String? {
        let name = L10n.language == "id" ? "CHANGELOG.id" : "CHANGELOG"
        guard let url = Bundle.main.url(forResource: name, withExtension: "md") ?? Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let md = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Changelog.section(md, version: current)
    }
}

// MARK: - Windows

enum UpdateWindow {
    private static var window: NSWindow?
    static func show() { window = present(window, title: L("update.title"), size: CGSize(width: 480, height: 460), UpdateView { window?.close() }) }
}

enum WhatsNewWindow {
    private static var window: NSWindow?
    static func show() {
        window = present(window, title: L("update.whatsNewTitle", UpdateService.shared.current), size: CGSize(width: 480, height: 460),
                         WhatsNewView { window?.close() })
    }
}

private func present<V: View>(_ existing: NSWindow?, title: String, size: CGSize, _ view: V) -> NSWindow {
    let w = existing ?? NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    w.title = title
    w.isReleasedWhenClosed = false
    w.contentView = NSHostingView(rootView: view)
    if existing == nil { w.center() }
    NSApp.activate()
    w.makeKeyAndOrderFront(nil)
    return w
}

private struct UpdateView: View {
    var done: () -> Void
    private var s: UpdateService { UpdateService.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch s.state {
            case .checking, .idle:
                HStack { ProgressView().controlSize(.small); SwiftUI.Text(L("update.checking")) }
                Spacer()
            case .upToDate:
                Label(L("update.upToDate", s.current), systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.headline)
                Spacer()
                HStack { Spacer(); Button(L("update.ok")) { done() }.keyboardShortcut(.defaultAction) }
            case .failed:
                Label(L("update.failed"), systemImage: "wifi.exclamationmark").foregroundStyle(.orange)
                Spacer()
                HStack { Spacer(); Button(L("update.later")) { done() }; Button(L("update.retry")) { s.check(manual: true) }.keyboardShortcut(.defaultAction) }
            case .available(let r):
                SwiftUI.Text(L("update.available", r.version?.description ?? r.tag)).font(.title2.bold())
                SwiftUI.Text(L("update.youHave", s.current)).foregroundStyle(.secondary)
                ScrollView { ChangelogText(markdown: r.body ?? "").frame(maxWidth: .infinity, alignment: .leading) }
                    .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                SwiftUI.Text(L("update.notNotarized")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(L("update.skip")) { s.skip(r); done() }
                    Spacer()
                    Button(L("update.later")) { done() }.keyboardShortcut(.cancelAction)
                    Button(L("update.download")) { NSWorkspace.shared.open(r.downloadURL); done() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 480, height: 460, alignment: .topLeading)
    }
}

private struct WhatsNewView: View {
    var done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SwiftUI.Text(L("update.whatsNewTitle", UpdateService.shared.current)).font(.title2.bold())
            ScrollView { ChangelogText(markdown: UpdateService.shared.whatsNew() ?? "").frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                Link(L("update.allChanges"), destination: UpdateService.releasesPage)
                Spacer()
                Button(L("update.ok")) { done() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 460, alignment: .topLeading)
    }
}

/// Just enough markdown for changelogs and release notes: headings, bullets, inline bold/code/links.
struct ChangelogText: View {
    var markdown: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(markdown.split(separator: "\n", omittingEmptySubsequences: true).enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#") {
                    SwiftUI.Text(inline(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))).font(.headline).padding(.top, 4)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        SwiftUI.Text("•")
                        SwiftUI.Text(inline(String(line.dropFirst(2)))).fixedSize(horizontal: false, vertical: true)
                    }
                } else if !line.hasPrefix("```"), !line.hasPrefix("---") {
                    SwiftUI.Text(inline(line)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
