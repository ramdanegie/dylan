import AppKit
import DylanCore

/// Whether Dylan may send Apple events to an app. Asking macOS can block for good when the target does not answer
/// (seen on macOS 27.2: Dylan froze for hours inside the check on a Spotify event), so the main thread only reads the
/// last answer and every check runs in the background.
enum Automation {
    private static var answers: [String: Bool] = [:]
    private static var pending: Set<String> = []

    /// The last answer (false until the first arrives), plus a fresh check in the background, one at a time per app.
    /// `onGrant` runs when the answer turns to allowed, e.g. to load what is already playing.
    static func allowed(_ id: String, onGrant: @escaping @MainActor () -> Void = {}) -> Bool {
        if pending.insert(id).inserted {
            Task.detached {
                let ok = ask(id, prompt: false)
                await MainActor.run {
                    pending.remove(id)
                    let was = answers[id] == true
                    answers[id] = ok
                    if ok && !was { onGrant() }
                }
            }
        }
        return answers[id] == true
    }

    /// Blocking: never call on the main thread. `prompt` shows the macOS dialog when the user has not decided yet.
    nonisolated static func ask(_ id: String, prompt: Bool) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: id)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, prompt) == noErr
    }
}

/// Spotify & Apple Music through distributed notifications + AppleScript. PRD §F5, spike T0.3.
/// No polling: position is extrapolated from the last event while playing.
final class MediaProvider {
    static let shared = MediaProvider()
    static let spotifyID = "com.spotify.client"
    static let musicID = "com.apple.Music"

    private var observers: [NSObjectProtocol] = []
    private var artworkTask: URLSessionDataTask?
    private(set) var active = false

    func start() {
        guard !active else { return }
        active = true
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { n in
            let info = PlayerInfo(n.userInfo)
            MainActor.assumeIsolated { MediaProvider.shared.spotifyChanged(info) }
        })
        observers.append(dnc.addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { n in
            let info = PlayerInfo(n.userInfo)
            MainActor.assumeIsolated { MediaProvider.shared.musicChanged(info) }
        })
        // Pick up whatever is already playing, but only if Automation was granted before:
        // the permission prompt belongs to the first media control (PRD §2.7), not to app launch.
        if canQuery(Self.spotifyID) { refreshSpotify() } else if canQuery(Self.musicID) { refreshMusic() }
    }

    func stop() {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
        active = false
        AppModel.shared.mediaChanged(nil)
    }

    private func isRunning(_ id: String) -> Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty }

    /// Background queries run only when the app is running and Automation is already allowed,
    /// so they can neither launch Spotify/Music nor pop a permission prompt.
    private func canQuery(_ id: String) -> Bool {
        guard isRunning(id) else { return false }
        return Automation.allowed(id) {
            // First answer (at launch, or just granted): pick up what is already playing.
            let p = MediaProvider.shared, source = AppModel.shared.media?.source
            guard p.active else { return }
            if id == Self.spotifyID, source == nil || source == .spotify { p.refreshSpotify() }
            if id == Self.musicID, source == nil || source == .music { p.refreshMusic() }
        }
    }

    /// Onboarding: ask for Automation now. macOS can only ask while the target app is running.
    /// Returns false when neither Spotify nor Music is open.
    func requestAutomation() -> Bool {
        guard let id = [Self.spotifyID, Self.musicID].first(where: isRunning) else { return false }
        Task.detached {
            _ = Automation.ask(id, prompt: true)
            await MainActor.run { MediaProvider.shared.start(); if id == Self.spotifyID { MediaProvider.shared.refreshSpotify() } }
        }
        return true
    }

    // MARK: Events

    private func spotifyChanged(_ info: PlayerInfo) {
        guard info.state != "Stopped" else { if AppModel.shared.media?.source == .spotify { AppModel.shared.mediaChanged(nil) }; return }
        var m = MediaState(source: .spotify, title: info.name, artist: info.artist, album: info.album,
                           isPlaying: info.state == "Playing", position: info.position,
                           duration: info.durationMS / 1000, positionAt: Date())
        m.artworkKey = info.trackID
        keepArtwork(&m)
        AppModel.shared.mediaChanged(m)
        if canQuery(Self.spotifyID) {
            if m.artwork == nil { fetchSpotifyArtwork(trackKey: m.artworkKey) }
            refreshSpotifyExtras()
        }
    }

    private func musicChanged(_ info: PlayerInfo) {
        guard info.state != "Stopped" else { if AppModel.shared.media?.source == .music { AppModel.shared.mediaChanged(nil) }; return }
        // Position is not in the notification; ask once when allowed, otherwise show what we have.
        if canQuery(Self.musicID) { refreshMusic(); return }
        var m = MediaState(source: .music, title: info.name, artist: info.artist, album: info.album,
                           isPlaying: info.state == "Playing", position: 0, duration: info.durationMS / 1000, positionAt: Date())
        m.artworkKey = info.trackID
        keepArtwork(&m)
        AppModel.shared.mediaChanged(m)
    }

    private func keepArtwork(_ m: inout MediaState) {
        if let old = AppModel.shared.media, old.artworkKey == m.artworkKey {
            m.artwork = old.artwork; m.shuffle = old.shuffle; m.repeating = old.repeating; m.volume = old.volume
        }
    }

    // MARK: AppleScript queries

    fileprivate func refreshSpotify() {
        let ID = Self.spotifyID
        let script = """
        tell application id "com.spotify.client"
          set s to player state as string
          if s is "stopped" then return s
          set t to current track
          return s & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & ((duration of t) as string) & linefeed & (player position as string) & linefeed & (id of t) & linefeed & (shuffling as string) & linefeed & (repeating as string) & linefeed & (sound volume as string)
        end tell
        """
        guard let r = run(script, app: ID) else { return }
        let f = r.components(separatedBy: "\n")
        guard f.count >= 10, f[0] != "stopped" else { AppModel.shared.mediaChanged(nil); return }
        var m = MediaState(source: .spotify, title: f[1], artist: f[2], album: f[3], isPlaying: f[0] == "playing",
                           position: num(f[5]), duration: num(f[4]) / 1000, positionAt: Date())
        m.artworkKey = f[6]; m.shuffle = f[7] == "true"; m.repeating = f[8] == "true"; m.volume = Int(num(f[9]))
        keepArtwork(&m)
        AppModel.shared.mediaChanged(m)
        if m.artwork == nil { fetchSpotifyArtwork(trackKey: m.artworkKey) }
    }

    private func refreshSpotifyExtras() {
        let ID = Self.spotifyID
        let script = """
        tell application id "com.spotify.client" to return (shuffling as string) & linefeed & (repeating as string) & linefeed & (sound volume as string)
        """
        guard let r = run(script, app: ID) else { return }
        let f = r.components(separatedBy: "\n")
        guard f.count >= 3, var m = AppModel.shared.media, m.source == .spotify else { return }
        m.shuffle = f[0] == "true"; m.repeating = f[1] == "true"; m.volume = Int(num(f[2]))
        AppModel.shared.mediaChanged(m)
    }

    private func refreshMusic() {
        let ID = Self.musicID
        let script = """
        tell application id "com.apple.Music"
          set s to player state as string
          if s is "stopped" then return s
          set t to current track
          return s & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & ((duration of t) as string) & linefeed & (player position as string) & linefeed & (persistent ID of t) & linefeed & (shuffle enabled as string) & linefeed & (song repeat as string) & linefeed & (sound volume as string)
        end tell
        """
        guard let r = run(script, app: ID) else { return }
        let f = r.components(separatedBy: "\n")
        guard f.count >= 10, f[0] != "stopped" else { AppModel.shared.mediaChanged(nil); return }
        var m = MediaState(source: .music, title: f[1], artist: f[2], album: f[3], isPlaying: f[0] == "playing",
                           position: num(f[5]), duration: num(f[4]), positionAt: Date())
        m.artworkKey = f[6]; m.shuffle = f[7] == "true"; m.repeating = f[8] != "off"; m.volume = Int(num(f[9]))
        keepArtwork(&m)
        if m.artwork == nil, let data = runData("tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track", app: ID) {
            m.artwork = NSImage(data: data)
        }
        AppModel.shared.mediaChanged(m)
    }

    /// Spotify only exposes an artwork URL (its CDN). Fetched once per track, cached in memory.
    private func fetchSpotifyArtwork(trackKey: String?) {
        guard let url = run("tell application id \"com.spotify.client\" to return artwork url of current track", app: Self.spotifyID)
            .flatMap(URL.init(string:)), url.scheme == "https" else { return }
        artworkTask?.cancel()
        artworkTask = URLSession.shared.dataTask(with: url) { @Sendable data, _, _ in
            guard let data else { return }
            Task { @MainActor in
                guard var m = AppModel.shared.media, m.artworkKey == trackKey, let img = NSImage(data: data) else { return }
                m.artwork = img
                AppModel.shared.mediaChanged(m)
            }
        }
        artworkTask?.resume()
    }

    // MARK: Controls

    private var appID: String? {
        switch AppModel.shared.media?.source {
        case .spotify: return Self.spotifyID
        case .music: return Self.musicID
        case .browser, .vlc: return nil
        case nil: return isRunning(Self.spotifyID) ? Self.spotifyID : (isRunning(Self.musicID) ? Self.musicID : nil)
        }
    }

    /// User-initiated, so it may show the Automation prompt once. Never sends to an app that is not
    /// running (`tell application` would launch it).
    private func control(_ command: String) {
        if let s = AppModel.shared.media?.source, s == .browser || s == .vlc {
            let action = ["playpause": "playpause", "next track": "next", "previous track": "previous"][command]
            if let action { OtherPlayersProvider.shared.control(action) }
            return
        }
        guard let id = appID else { return }
        _ = run("tell application id \"\(id)\" to \(command)", app: id, userInitiated: true)
        if id == Self.musicID, canQuery(id) { refreshMusic() }
    }

    func playPause() { control("playpause") }

    /// Quick play (FR-60). The URI was validated by `SpotifyLink`, so it is safe inside the script.
    /// Opens Spotify in the background first when it is not running.
    func play(_ item: QuickPlayItem) {
        guard SpotifyLink.uri(from: item.uri) == item.uri else { return }
        let script = "tell application id \"\(Self.spotifyID)\" to play track \"\(item.uri)\""
        if isRunning(Self.spotifyID) { _ = run(script, app: Self.spotifyID, userInitiated: true); return }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.spotifyID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: app, configuration: config) { _, _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                _ = MediaProvider.shared.run(script, app: Self.spotifyID, userInitiated: true)
            }
        }
    }

    /// Apple Music only: Spotify has no AppleScript for saving songs (that needs the Web API, FR-64).
    /// Apple Music: favourite through AppleScript. Spotify: save to library with the Spotify account (FR-64).
    var canLove: Bool {
        switch AppModel.shared.media?.source {
        case .music: return true
        case .spotify: return SpotifyAccount.shared.savedCurrent != nil
        case .browser, .vlc, nil: return false
        }
    }
    var loved: Bool { AppModel.shared.media?.source == .spotify && SpotifyAccount.shared.savedCurrent == true }
    func toggleLove() {
        guard canLove else { return }
        if AppModel.shared.media?.source == .spotify { SpotifyAccount.shared.toggleSaved(); return }
        control("set favorited of current track to not (favorited of current track)")
    }
    func next() { control("next track") }
    func previous() { control("previous track") }

    func seek(to seconds: TimeInterval) {
        guard AppModel.shared.media?.hasFullControls != false else { return }
        control("set player position to \(Int(seconds))")
        if var m = AppModel.shared.media { m.position = seconds; m.positionAt = Date(); AppModel.shared.mediaChanged(m) }
    }

    func setVolume(_ v: Int) {
        control("set sound volume to \(max(0, min(100, v)))")
        if var m = AppModel.shared.media { m.volume = v; AppModel.shared.mediaChanged(m) }
    }

    func toggleShuffle() {
        guard var m = AppModel.shared.media else { return }
        m.shuffle.toggle()
        control(m.source == .spotify ? "set shuffling to \(m.shuffle)" : "set shuffle enabled to \(m.shuffle)")
        AppModel.shared.mediaChanged(m)
    }

    func toggleRepeat() {
        guard var m = AppModel.shared.media else { return }
        m.repeating.toggle()
        control(m.source == .spotify ? "set repeating to \(m.repeating)" : "set song repeat to \(m.repeating ? "all" : "off")")
        AppModel.shared.mediaChanged(m)
    }

    // MARK: AppleScript

    private func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    /// NSAppleScript runs on the main thread, so every script gets a 2 s Apple-event timeout:
    /// a hung Spotify must not freeze the notch or the socket (permission hooks wait on it).
    fileprivate func run(_ source: String, app: String, userInitiated: Bool = false) -> String? {
        guard userInitiated ? isRunning(app) : canQuery(app) else { return nil }
        var err: NSDictionary?
        let r = NSAppleScript(source: "with timeout of 2 seconds\n\(source)\nend timeout")?.executeAndReturnError(&err)
        if let err {
            let code = err[NSAppleScript.errorNumber] as? Int ?? 0
            // -1743: the user has not allowed Automation for this app.
            AppModel.shared.lastError = code == -1743 ? L("error.automation") : nil
            return nil
        }
        return r?.stringValue
    }

    private func runData(_ source: String, app: String) -> Data? {
        guard canQuery(app) else { return nil }
        var err: NSDictionary?
        let r = NSAppleScript(source: "with timeout of 2 seconds\n\(source)\nend timeout")?.executeAndReturnError(&err)
        return err == nil ? r?.data : nil
    }
}

/// Sendable copy of a player notification's userInfo.
nonisolated struct PlayerInfo: Sendable {
    var state, name, artist, album: String
    var position, durationMS: Double
    var trackID: String?

    init(_ u: [AnyHashable: Any]?) {
        let u = u ?? [:]
        state = u["Player State"] as? String ?? "Stopped"
        name = u["Name"] as? String ?? ""
        artist = u["Artist"] as? String ?? ""
        album = u["Album"] as? String ?? ""
        position = u["Playback Position"] as? Double ?? 0
        durationMS = (u["Duration"] as? Double) ?? (u["Total Time"] as? Double) ?? 0
        trackID = u["Track ID"] as? String ?? (u["PersistentID"] as? NSNumber)?.stringValue
    }
}
