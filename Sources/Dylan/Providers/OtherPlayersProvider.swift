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
    private var lastBrowser: String?
    /// Tab titles are read off the main thread, at most every 10 s while the same browser keeps playing.
    private var lastTabQuery = Date.distantPast
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
        guard m.features.isEnabled(.otherPlayers), m.features.isEnabled(.media) else { return }
        // Spotify and Music have their own events and win.
        if let s = m.media?.source, s == .spotify || s == .music, m.media?.isPlaying == true { return }
        let candidates = Set(BrowserMedia.browsers.keys).union([Self.vlcID])
        let running = NSWorkspace.shared.runningApplications.filter { candidates.contains($0.bundleIdentifier ?? "") }
        guard !running.isEmpty else { clearIfOurs(); return }
        // VLC has a proper scripting dictionary: ask it directly.
        if running.contains(where: { $0.bundleIdentifier == Self.vlcID }) {
            query(BrowserMedia.vlcScript, app: Self.vlcID) { out in
                guard let v = out.flatMap(BrowserMedia.parseVLC) else { return }
                OtherPlayersProvider.shared.publish(MediaState(source: .vlc, title: v.title, artist: "VLC", album: "", isPlaying: v.playing,
                                                               position: v.position, duration: v.duration, positionAt: Date(),
                                                               artwork: nil, artworkKey: "vlc:" + v.title, appBundleID: Self.vlcID))
            }
            return
        }
        // Browsers: only the one producing sound, and only then is AppleScript used.
        let playing = Set(AudioTap.processes().filter(\.playing).compactMap(\.app.bundleIdentifier))
        guard let browser = running.first(where: { playing.contains($0.bundleIdentifier ?? "") && BrowserMedia.browsers[$0.bundleIdentifier ?? ""] != nil }),
              let id = browser.bundleIdentifier else {
            // Paused: keep the last item, shown as paused.
            if var cur = m.media, cur.source == .browser, cur.isPlaying { cur.isPlaying = false; publish(cur) }
            else if m.media?.source == .vlc { clearIfOurs() }   // VLC quit
            return
        }
        if var cur = m.media, cur.source == .browser, cur.appBundleID == id, Date().timeIntervalSince(lastTabQuery) < 10 {
            if !cur.isPlaying { cur.isPlaying = true; publish(cur) }
            return
        }
        lastTabQuery = Date()
        lastBrowser = id
        query(BrowserMedia.tabsScript(bundleID: id), app: id) { out in
            guard let item = out.flatMap({ BrowserMedia.pick(BrowserMedia.parseTabs($0)) }) else { return }
            OtherPlayersProvider.shared.publish(MediaState(
                source: .browser, title: item.title, artist: item.artist.isEmpty ? "\(item.site) · \(BrowserMedia.browsers[id] ?? "")" : item.artist,
                album: item.artist.isEmpty ? "" : item.site, isPlaying: true, position: 0, duration: 0, positionAt: Date(),
                artwork: nil, artworkKey: "web:" + item.title, appBundleID: id))
        }
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

    private func canAutomate(_ app: String) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: app)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) == noErr
    }

    private func publish(_ s: MediaState) {
        if AppModel.shared.media != s { AppModel.shared.mediaChanged(s) }
    }

    private func clearIfOurs() {
        if let s = AppModel.shared.media?.source, s == .browser || s == .vlc { AppModel.shared.mediaChanged(nil) }
    }

    /// Background polls never prompt: the first Automation prompt comes from the user's own action (a control).
    private func run(_ source: String, app: String) -> String? {
        let target = NSAppleEventDescriptor(bundleIdentifier: app)
        guard AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) == noErr else { return nil }
        var err: NSDictionary?
        let r = NSAppleScript(source: "with timeout of 2 seconds\n\(source)\nend timeout")?.executeAndReturnError(&err)
        return err == nil ? r?.stringValue : nil
    }

    /// Settings → Media: ask each running browser (and VLC) for Automation now, while the user is looking.
    func requestAccess() {
        let ids = Set(BrowserMedia.browsers.keys).union([Self.vlcID])
        let apps = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).filter { ids.contains($0) }
        Task.detached {
            for id in apps {
                let target = NSAppleEventDescriptor(bundleIdentifier: id)
                _ = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
            }
            await MainActor.run { OtherPlayersProvider.shared.poll() }
        }
    }

    // MARK: Controls

    func control(_ action: String) {
        guard let m = AppModel.shared.media else { return }
        if m.source == .vlc {
            let cmd = ["playpause": "play", "next": "next", "previous": "previous"][action] ?? ""
            guard !cmd.isEmpty else { return }
            _ = run("tell application id \"\(Self.vlcID)\" to \(cmd)", app: Self.vlcID)
        } else {
            // NX_KEYTYPE_PLAY 16, NEXT 17, PREVIOUS 18: macOS sends them to the Now Playing app (the browser tab).
            guard let key = ["playpause": 16, "next": 17, "previous": 18][action] else { return }
            Self.mediaKey(key)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { OtherPlayersProvider.shared.poll() } }
    }

    static func mediaKey(_ key: Int) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (key << 16) | ((down ? 0xA : 0xB) << 8)
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                               context: nil, subtype: 8, data1: data1, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
