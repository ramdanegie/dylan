import AppKit
import DylanCore

/// Other players (FR-11): YouTube, YouTube Music, SoundCloud, Spotify Web… in Chrome, Safari, Arc, Edge, Brave,
/// and VLC. No MediaRemote (private, restricted since macOS 15.4): Core Audio says which app is producing sound,
/// AppleScript gives the tab title/URL or VLC's item, and play/pause/next/previous are the system media keys
/// (routed by macOS to the app that is playing). Opt-in: each browser asks for Automation once.
/// Polls every 3 s only while one of these apps is running and Spotify/Music are not playing.
final class OtherPlayersProvider {
    static let shared = OtherPlayersProvider()
    static let vlcID = "org.videolan.vlc"
    private var timer: Timer?
    /// Tab titles are read off the main thread, at most every 10 s per browser.
    private var lastTabQuery: [String: Date] = [:]
    /// The tab shown now (window/tab numbers), for the controls.
    private var lastItem: BrowserMedia.Item?
    private var querying = false

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 3, repeats: true) { _ in MainActor.assumeIsolated { OtherPlayersProvider.shared.poll() } }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let s = AppModel.shared.media?.source, s == .browser || s == .vlc { AppModel.shared.mediaChanged(nil) }
    }

    private func poll() {
        let m = AppModel.shared
        guard m.features.isEnabled(.otherPlayers), m.features.isEnabled(.media), !Self.fullPlayerPlaying else { return }
        let candidates = Set(BrowserMedia.browsers.keys).union([Self.vlcID])
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)).intersection(candidates)
        // The app behind the current item quit.
        if let cur = m.media, cur.source == .browser || cur.source == .vlc, let id = cur.appBundleID, !running.contains(id) { clearIfOurs() }
        guard !running.isEmpty else { return }
        let playing = Set(AudioTap.processes().filter(\.playing).compactMap(\.app.bundleIdentifier))
        let browser = BrowserMedia.browsers.keys.sorted().first { running.contains($0) && playing.contains($0) }
        // VLC only when it is the one making sound, or it is already shown and no browser plays.
        if running.contains(Self.vlcID), playing.contains(Self.vlcID) || (m.media?.source == .vlc && browser == nil) {
            query(BrowserMedia.vlcScript, app: Self.vlcID) { out in
                guard let out else { return }   // timeout: keep what is shown
                guard let v = BrowserMedia.parseVLC(out) else {
                    if AppModel.shared.media?.source == .vlc { OtherPlayersProvider.shared.clearIfOurs() }   // stopped, playlist cleared
                    return
                }
                OtherPlayersProvider.shared.publish(MediaState(source: .vlc, title: v.title, artist: "VLC", album: "", isPlaying: v.playing,
                                                               position: v.position, duration: v.duration, positionAt: Date(),
                                                               artwork: nil, artworkKey: "vlc:" + v.title, appBundleID: Self.vlcID))
            }
            return
        }
        guard let id = browser else {
            // Nothing plays: a browser item stays, shown as paused (its app is still running, checked above).
            if var cur = m.media, cur.source == .browser, cur.isPlaying { cur.isPlaying = false; publish(cur) }
            return
        }
        // At most one tab listing per browser every 10 s, whatever the last answer was (a Meet call, a game).
        if let last = lastTabQuery[id], Date().timeIntervalSince(last) < 10 {
            if var cur = m.media, cur.source == .browser, cur.appBundleID == id, !cur.isPlaying { cur.isPlaying = true; publish(cur) }
            return
        }
        lastTabQuery[id] = Date()
        query(BrowserMedia.tabsScript(bundleID: id), app: id) { out in
            guard let out else { return }
            guard let item = BrowserMedia.pick(BrowserMedia.parseTabs(out)) else {
                // The media tab is gone while the browser still makes sound (a call): drop the old title.
                if AppModel.shared.media?.source == .browser, AppModel.shared.media?.appBundleID == id { OtherPlayersProvider.shared.clearIfOurs() }
                return
            }
            OtherPlayersProvider.shared.lastItem = item
            OtherPlayersProvider.shared.publish(MediaState(
                source: .browser, title: item.title, artist: item.artist.isEmpty ? "\(item.site) · \(BrowserMedia.browsers[id] ?? "")" : item.artist,
                album: item.artist.isEmpty ? "" : item.site, isPlaying: true, position: 0, duration: 0, positionAt: Date(),
                artwork: nil, artworkKey: "web:" + item.title, appBundleID: id))
        }
    }

    /// Spotify or Music playing: they have their own events and always win.
    static var fullPlayerPlaying: Bool {
        guard let m = AppModel.shared.media else { return false }
        return m.hasFullControls && m.isPlaying
    }

    private func publish(_ s: MediaState) {
        // Re-checked here: a query result can arrive seconds after Spotify started.
        guard !Self.fullPlayerPlaying, AppModel.shared.media != s else { return }
        AppModel.shared.mediaChanged(s)
    }

    /// osascript in the background: a browser with hundreds of tabs must not stall the notch. Never prompts
    /// (checked first); the child's Automation is Dylan's, as its responsible process.
    private func query(_ script: String, app: String, then: @escaping @MainActor (String?) -> Void) {
        guard !querying, canAutomate(app) else { return }
        querying = true
        Task.detached {
            let out = Shell.run("/usr/bin/osascript", ["-e", "with timeout of 3 seconds", "-e", script, "-e", "end timeout"], timeout: 4)
            await MainActor.run {
                OtherPlayersProvider.shared.querying = false
                guard OtherPlayersProvider.shared.timer != nil else { return }
                then(out?.trimmingCharacters(in: .newlines))
            }
        }
    }

    private func canAutomate(_ app: String) -> Bool { Automation.allowed(app) }

    private func clearIfOurs() {
        if let s = AppModel.shared.media?.source, s == .browser || s == .vlc { AppModel.shared.mediaChanged(nil) }
    }


    /// Settings → Media: ask each running browser (and VLC) for Automation now, while the user is looking.
    func requestAccess() {
        let ids = Set(BrowserMedia.browsers.keys).union([Self.vlcID])
        let apps = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).filter { ids.contains($0) }
        Task.detached {
            for id in apps { _ = Automation.ask(id, prompt: true) }
            await MainActor.run { OtherPlayersProvider.shared.poll() }
        }
    }

    // MARK: Controls

    /// Browser tabs cannot be paused from outside on macOS 27.2: synthesized media keys and keys sent to a
    /// background Chrome are both ignored (tested). So play/pause runs a fixed script in the tab when the
    /// user has turned on "Allow JavaScript from Apple Events" in that browser, and otherwise (and for
    /// next/previous) the buttons bring the media tab forward so the user can control it there.
    func control(_ action: String) {
        guard let m = AppModel.shared.media else { return }
        if m.source == .vlc {
            let cmd = ["playpause": "play", "next": "next", "previous": "previous"][action] ?? ""
            guard !cmd.isEmpty else { return }
            _ = run("tell application id \"\(Self.vlcID)\" to \(cmd)", app: Self.vlcID)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { OtherPlayersProvider.shared.poll() } }
            return
        }
        guard let item = lastItem, let id = m.appBundleID else { return }
        if action == "playpause", let js = BrowserMedia.tabScript(bundleID: id, action: "toggle", window: item.window, tab: item.tab),
           run(js, app: id) == "ok" {
            lastTabQuery[id] = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { MainActor.assumeIsolated { OtherPlayersProvider.shared.poll() } }
            return
        }
        if let show = BrowserMedia.tabScript(bundleID: id, action: "show", window: item.window, tab: item.tab) { _ = run(show, app: id) }
    }

    /// Run on the main thread for user actions only (a click): short scripts against an allowed app.
    private func run(_ source: String, app: String) -> String? {
        guard canAutomate(app) else { return nil }
        var err: NSDictionary?
        let r = NSAppleScript(source: "with timeout of 2 seconds\n\(source)\nend timeout")?.executeAndReturnError(&err)
        return err == nil ? r?.stringValue : nil
    }
}
