import AppKit
import DylanCore

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
        // Pick up whatever is already playing.
        if isRunning(Self.spotifyID) { refreshSpotify() } else if isRunning(Self.musicID) { refreshMusic() }
    }

    func stop() {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
        active = false
        AppModel.shared.mediaChanged(nil)
    }

    private func isRunning(_ id: String) -> Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty }

    // MARK: Events

    private func spotifyChanged(_ info: PlayerInfo) {
        guard info.state != "Stopped" else { AppModel.shared.mediaChanged(nil); return }
        var m = MediaState(source: .spotify, title: info.name, artist: info.artist, album: info.album,
                           isPlaying: info.state == "Playing", position: info.position,
                           duration: info.durationMS / 1000, positionAt: Date())
        m.artworkKey = info.trackID
        keepArtwork(&m)
        AppModel.shared.mediaChanged(m)
        if m.artwork == nil { fetchSpotifyArtwork(trackKey: m.artworkKey) }
        refreshSpotifyExtras()
    }

    private func musicChanged(_ info: PlayerInfo) {
        guard info.state != "Stopped" else { AppModel.shared.mediaChanged(nil); return }
        // Position is not in the notification; ask once.
        refreshMusic()
    }

    private func keepArtwork(_ m: inout MediaState) {
        if let old = AppModel.shared.media, old.artworkKey == m.artworkKey {
            m.artwork = old.artwork; m.shuffle = old.shuffle; m.repeating = old.repeating; m.volume = old.volume
        }
    }

    // MARK: AppleScript queries

    private func refreshSpotify() {
        let script = """
        tell application id "com.spotify.client"
          set s to player state as string
          if s is "stopped" then return s
          set t to current track
          return s & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & ((duration of t) as string) & linefeed & (player position as string) & linefeed & (id of t) & linefeed & (shuffling as string) & linefeed & (repeating as string) & linefeed & (sound volume as string)
        end tell
        """
        guard let r = run(script) else { return }
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
        let script = """
        tell application id "com.spotify.client" to return (shuffling as string) & linefeed & (repeating as string) & linefeed & (sound volume as string)
        """
        guard let r = run(script) else { return }
        let f = r.components(separatedBy: "\n")
        guard f.count >= 3, var m = AppModel.shared.media, m.source == .spotify else { return }
        m.shuffle = f[0] == "true"; m.repeating = f[1] == "true"; m.volume = Int(num(f[2]))
        AppModel.shared.mediaChanged(m)
    }

    private func refreshMusic() {
        let script = """
        tell application id "com.apple.Music"
          set s to player state as string
          if s is "stopped" then return s
          set t to current track
          return s & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & ((duration of t) as string) & linefeed & (player position as string) & linefeed & (persistent ID of t) & linefeed & (shuffle enabled as string) & linefeed & (song repeat as string) & linefeed & (sound volume as string)
        end tell
        """
        guard let r = run(script) else { return }
        let f = r.components(separatedBy: "\n")
        guard f.count >= 10, f[0] != "stopped" else { AppModel.shared.mediaChanged(nil); return }
        var m = MediaState(source: .music, title: f[1], artist: f[2], album: f[3], isPlaying: f[0] == "playing",
                           position: num(f[5]), duration: num(f[4]), positionAt: Date())
        m.artworkKey = f[6]; m.shuffle = f[7] == "true"; m.repeating = f[8] != "off"; m.volume = Int(num(f[9]))
        keepArtwork(&m)
        if m.artwork == nil, let data = runData("tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track") {
            m.artwork = NSImage(data: data)
        }
        AppModel.shared.mediaChanged(m)
    }

    /// Spotify only exposes an artwork URL (its CDN). Fetched once per track, cached in memory.
    private func fetchSpotifyArtwork(trackKey: String?) {
        guard let url = run("tell application id \"com.spotify.client\" to return artwork url of current track")
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
        case nil: return isRunning(Self.spotifyID) ? Self.spotifyID : (isRunning(Self.musicID) ? Self.musicID : nil)
        }
    }

    /// Never sends to an app that is not running: `tell application` would launch it.
    private func control(_ command: String) {
        guard let id = appID, isRunning(id) else { return }
        _ = run("tell application id \"\(id)\" to \(command)")
        if id == Self.musicID { refreshMusic() }
    }

    func playPause() { control("playpause") }
    func next() { control("next track") }
    func previous() { control("previous track") }

    func seek(to seconds: TimeInterval) {
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

    private func run(_ source: String) -> String? {
        var err: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err {
            let code = err[NSAppleScript.errorNumber] as? Int ?? 0
            // -1743: the user has not allowed Automation for this app.
            AppModel.shared.lastError = code == -1743 ? L("error.automation") : nil
            return nil
        }
        return r?.stringValue
    }

    private func runData(_ source: String) -> Data? {
        var err: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&err)
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
