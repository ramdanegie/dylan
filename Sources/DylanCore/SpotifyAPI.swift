import CryptoKit
import Foundation

/// Spotify Web API with Authorization Code + PKCE (FR-64): no client secret, loopback redirect, refresh token
/// in the Keychain. Endpoints follow the February 2026 changes (`/me/library` with URIs).
public enum SpotifyAPI {
    public static let port: UInt16 = 47823
    public static let redirectURI = "http://127.0.0.1:47823/callback"
    public static let scopes = ["user-library-read", "user-library-modify", "playlist-read-private", "user-read-playback-state"]

    // MARK: PKCE (RFC 7636)

    public static func verifier<G: RandomNumberGenerator>(using g: inout G) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<64).map { _ in chars.randomElement(using: &g)! })
    }

    public static func challenge(_ verifier: String) -> String {
        base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    public static func authorizeURL(clientID: String, challenge: String, state: String) -> URL {
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "response_type", value: "code"), .init(name: "client_id", value: clientID),
            .init(name: "scope", value: scopes.joined(separator: " ")), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge), .init(name: "redirect_uri", value: redirectURI),
            .init(name: "state", value: state),
        ]
        return c.url!
    }

    public static func tokenBody(code: String, verifier: String, clientID: String) -> String {
        form(["grant_type": "authorization_code", "code": code, "redirect_uri": redirectURI, "client_id": clientID, "code_verifier": verifier])
    }

    public static func refreshBody(refreshToken: String, clientID: String) -> String {
        form(["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID])
    }

    static func form(_ p: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        return p.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&")
    }

    public struct Token: Equatable, Sendable {
        public var access: String
        public var refresh: String?
        public var expiresIn: TimeInterval
    }

    public static func parseToken(_ d: Data) -> Token? {
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let a = o["access_token"] as? String else { return nil }
        return Token(access: a, refresh: o["refresh_token"] as? String, expiresIn: (o["expires_in"] as? Double) ?? 3600)
    }

    /// The loopback callback's request line → the code, if the state matches. Errors (access_denied) → nil.
    public static func callbackCode(requestLine: String, state: String) -> String? {
        guard let q = callbackParams(requestLine), q["state"] == state, let code = q["code"], !code.isEmpty else { return nil }
        return code
    }

    /// Query of a `GET /callback?…` request line, or nil for anything else.
    static func callbackParams(_ requestLine: String) -> [String: String]? {
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET", let c = URLComponents(string: "http://127.0.0.1" + parts[1]), c.path == "/callback" else { return nil }
        return Dictionary((c.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Endpoints

    public static func libraryURL(_ uri: String, contains: Bool = false) -> URL? {
        guard SpotifyLink.uri(from: uri) == uri else { return nil }   // only well-formed spotify: URIs
        var c = URLComponents(string: "https://api.spotify.com/v1/me/library" + (contains ? "/contains" : ""))!
        c.queryItems = [.init(name: "uris", value: uri)]
        return c.url
    }

    public static let playlistsURL = URL(string: "https://api.spotify.com/v1/me/playlists?limit=30")!
    public static let queueURL = URL(string: "https://api.spotify.com/v1/me/player/queue?limit=3")!

    public static func parseContains(_ d: Data) -> Bool? { (try? JSONSerialization.jsonObject(with: d) as? [Bool])?.first }

    public struct Item: Equatable, Sendable { public var name: String; public var uri: String; public var detail: String? }

    public static func parsePlaylists(_ d: Data) -> [Item] {
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let items = o["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { i in
            guard let n = i["name"] as? String, let u = i["uri"] as? String, !n.isEmpty else { return nil }
            return Item(name: n, uri: u, detail: (i["owner"] as? [String: Any])?["display_name"] as? String)
        }
    }

    /// Next track in the queue: "Title — Artist".
    public static func parseQueueNext(_ d: Data) -> Item? {
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let next = (o["queue"] as? [[String: Any]])?.first,
              let n = next["name"] as? String, let u = next["uri"] as? String else { return nil }
        let artist = ((next["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String })?.joined(separator: ", ")
            ?? ((next["show"] as? [String: Any])?["name"] as? String)
        return Item(name: n, uri: u, detail: artist)
    }

    // MARK: Loopback redirect (127.0.0.1 only)

    /// Waits for the browser's redirect, answers it with a short page and returns the code (state checked).
    public static func waitForCallback(state: String, port: UInt16 = SpotifyAPI.port, timeout: TimeInterval) -> String? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(fd, 4) == 0 else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&p, 1, Int32(max(0, deadline.timeIntervalSinceNow) * 1000)) > 0 else { return nil }
            let c = accept(fd, nil, nil)
            guard c >= 0 else { continue }
            // A connection that sends nothing (browser preconnect) must not stall the sign-in.
            var tv = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            var one: Int32 = 1
            setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            var buf = [UInt8](repeating: 0, count: 8192)
            let n = read(c, &buf, buf.count)
            let line = n > 0 ? String(decoding: buf[0..<n], as: UTF8.self).components(separatedBy: "\r\n").first ?? "" : ""
            let code = SpotifyAPI.callbackCode(requestLine: line, state: state)
            // Only our own redirect (matching state) ends the wait; anything else on the port is answered and ignored.
            let isCallback = SpotifyAPI.callbackParams(line)?["state"] == state
            let html = isCallback ? (code != nil ? "Dylan is connected to Spotify. You can close this tab." : "Spotify sign-in was cancelled.") : "Not found"
            let response = "HTTP/1.1 \(isCallback ? "200 OK" : "404 Not Found")\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\nContent-Length: \(html.utf8.count)\r\n\r\n\(html)"
            _ = response.withCString { write(c, $0, strlen($0)) }
            close(c)
            if isCallback { return code }
        }
        return nil
    }
}
