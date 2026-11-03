import AppKit
import DylanCore

/// Spotify account (FR-64), opt-in: save the playing track, your playlists for quick play, and what plays
/// next. Authorization Code + PKCE with the user's own Client ID; the refresh token lives in the Keychain,
/// the access token in memory only. Network goes to accounts.spotify.com and api.spotify.com only.
@Observable
final class SpotifyAccount {
    static let shared = SpotifyAccount()

    var connected = Keychain.get("spotify.refresh") != nil
    var status: String?
    var playlists: [SpotifyAPI.Item] = []
    var next: SpotifyAPI.Item?
    var savedCurrent: Bool?
    @ObservationIgnored private var access: (token: String, until: Date)?
    @ObservationIgnored private var currentURI: String?
    @ObservationIgnored private var connecting = false

    var clientID: String { AppModel.shared.spotifyClientID.trimmingCharacters(in: .whitespaces) }

    // MARK: Sign in

    func connect() {
        guard !clientID.isEmpty, !connecting else { return }
        connecting = true
        var g = SystemRandomNumberGenerator()
        let verifier = SpotifyAPI.verifier(using: &g)
        let state = UUID().uuidString
        let id = clientID
        status = L("spotify.approveInBrowser")
        Task.detached {
            let code = SpotifyAPI.waitForCallback(state: state, timeout: 180)
            await MainActor.run {
                let s = SpotifyAccount.shared
                s.connecting = false
                guard let code else { s.status = L("spotify.signInFailed"); return }
                s.post(SpotifyAPI.tokenBody(code: code, verifier: verifier, clientID: id))
            }
        }
        NSWorkspace.shared.open(SpotifyAPI.authorizeURL(clientID: id, challenge: SpotifyAPI.challenge(verifier), state: state))
    }

    func disconnect() {
        Keychain.set(nil, "spotify.refresh")
        access = nil; connected = false
        playlists = []; next = nil; savedCurrent = nil; currentURI = nil
        status = nil
    }

    /// Token request (code exchange or refresh); keeps a rotated refresh token.
    private func post(_ body: String, then: (@MainActor (String) -> Void)? = nil) {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(body.utf8)
        URLSession.shared.dataTask(with: req) { @Sendable data, response, _ in
            let token = data.flatMap(SpotifyAPI.parseToken)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            Task { @MainActor in
                let s = SpotifyAccount.shared
                guard let token else {
                    // invalid_grant: the refresh token was revoked; sign in again.
                    if code == 400 { s.disconnect() }
                    s.status = L("spotify.signInFailed")
                    return
                }
                if let r = token.refresh { Keychain.set(r, "spotify.refresh") }
                s.access = (token.access, Date().addingTimeInterval(token.expiresIn - 60))
                if !s.connected { s.connected = true; s.status = nil; s.loadPlaylists() }
                then?(token.access)
            }
        }.resume()
    }

    private func withToken(_ f: @escaping @MainActor (String) -> Void) {
        if let a = access, a.until > Date() { f(a.token); return }
        guard let r = Keychain.get("spotify.refresh"), !clientID.isEmpty else { return }
        post(SpotifyAPI.refreshBody(refreshToken: r, clientID: clientID), then: f)
    }

    private func call(_ method: String, _ url: URL, then: (@Sendable (Data?, Int) -> Void)? = nil) {
        withToken { token in
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.httpMethod = method
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: req) { @Sendable data, response, _ in
                then?(data, (response as? HTTPURLResponse)?.statusCode ?? 0)
            }.resume()
        }
    }

    // MARK: Features

    func loadPlaylists() {
        guard connected else { return }
        call("GET", SpotifyAPI.playlistsURL) { data, _ in
            let list = data.map(SpotifyAPI.parsePlaylists) ?? []
            Task { @MainActor in SpotifyAccount.shared.playlists = list }
        }
    }

    /// The Spotify track changed: is it saved, and what plays next.
    func trackChanged(_ uri: String?) {
        guard connected, uri != currentURI else { return }
        currentURI = uri
        savedCurrent = nil; next = nil
        guard let uri, let url = SpotifyAPI.libraryURL(uri, contains: true) else { return }
        call("GET", url) { data, _ in
            let saved = data.flatMap(SpotifyAPI.parseContains)
            Task { @MainActor in if SpotifyAccount.shared.currentURI == uri { SpotifyAccount.shared.savedCurrent = saved } }
        }
        call("GET", SpotifyAPI.queueURL) { data, _ in
            let n = data.flatMap(SpotifyAPI.parseQueueNext)
            Task { @MainActor in if SpotifyAccount.shared.currentURI == uri { SpotifyAccount.shared.next = n } }
        }
    }

    func toggleSaved() {
        guard let uri = currentURI, let saved = savedCurrent, let url = SpotifyAPI.libraryURL(uri) else { return }
        savedCurrent = !saved
        call(saved ? "DELETE" : "PUT", url) { _, code in
            // Roll back when Spotify refused.
            if !(200..<300).contains(code) { Task { @MainActor in if SpotifyAccount.shared.currentURI == uri { SpotifyAccount.shared.savedCurrent = saved } } }
        }
    }
}
