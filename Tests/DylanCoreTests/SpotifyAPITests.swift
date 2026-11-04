import Foundation
import Testing
@testable import DylanCore

@Suite struct SpotifyAPITests {
    @Test func pkce() {
        // RFC 7636 appendix B.
        #expect(SpotifyAPI.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        var g = SystemRandomNumberGenerator()
        let v = SpotifyAPI.verifier(using: &g)
        #expect(v.count == 64 && v.allSatisfy { $0.isLetter || $0.isNumber || "-._~".contains($0) })
        let url = SpotifyAPI.authorizeURL(clientID: "abc", challenge: "ch", state: "st").absoluteString
        #expect(url.contains("code_challenge_method=S256") && url.contains("redirect_uri=http://127.0.0.1:47823/callback") && url.contains("state=st"))
        #expect(SpotifyAPI.tokenBody(code: "c&1", verifier: "v", clientID: "id")
                == "client_id=id&code=c%261&code_verifier=v&grant_type=authorization_code&redirect_uri=http%3A%2F%2F127.0.0.1%3A47823%2Fcallback")
    }

    @Test func callback() {
        #expect(SpotifyAPI.callbackCode(requestLine: "GET /callback?code=AQB&state=s1 HTTP/1.1", state: "s1") == "AQB")
        #expect(SpotifyAPI.callbackCode(requestLine: "GET /callback?code=AQB&state=evil HTTP/1.1", state: "s1") == nil)
        #expect(SpotifyAPI.callbackCode(requestLine: "GET /callback?error=access_denied&state=s1 HTTP/1.1", state: "s1") == nil)
        #expect(SpotifyAPI.callbackCode(requestLine: "GET /favicon.ico HTTP/1.1", state: "s1") == nil)
        #expect(SpotifyAPI.callbackCode(requestLine: "POST /callback?code=x&state=s1 HTTP/1.1", state: "s1") == nil)
    }

    @Test func responses() {
        #expect(SpotifyAPI.parseToken(Data(#"{"access_token":"A","refresh_token":"R","expires_in":3600}"#.utf8)) == .init(access: "A", refresh: "R", expiresIn: 3600))
        #expect(SpotifyAPI.parseToken(Data(#"{"error":"invalid_grant"}"#.utf8)) == nil)
        #expect(SpotifyAPI.parseContains(Data("[true]".utf8)) == true)
        let pl = SpotifyAPI.parsePlaylists(Data(#"{"items":[{"name":"Fokus Ngoding","uri":"spotify:playlist:37i9","owner":{"display_name":"Egie"}},{"name":"","uri":"x"}]}"#.utf8))
        #expect(pl == [.init(name: "Fokus Ngoding", uri: "spotify:playlist:37i9", detail: "Egie")])
        let q = SpotifyAPI.parseQueueNext(Data(#"{"currently_playing":{"name":"A"},"queue":[{"name":"Senja","uri":"spotify:track:1","artists":[{"name":"Arsa"}]}]}"#.utf8))
        #expect(q == .init(name: "Senja", uri: "spotify:track:1", detail: "Arsa"))
        #expect(SpotifyAPI.libraryURL("spotify:track:4iV5W9uYEdYUVa79Axb7Rh")?.absoluteString == "https://api.spotify.com/v1/me/library?uris=spotify:track:4iV5W9uYEdYUVa79Axb7Rh")
        #expect(SpotifyAPI.libraryURL("spotify:track:x\" & do shell script") == nil)
    }
}

@Suite struct SpotifyLoopbackTests {
    @Test func answersTheRedirectAndChecksState() async throws {
        let port: UInt16 = 47_899
        let waiting = Task.detached { SpotifyAPI.waitForCallback(state: "s1", port: port, timeout: 5) }
        try await Task.sleep(for: .milliseconds(200))
        // A stray request first (browsers ask for a favicon), then the real redirect.
        _ = try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/favicon.ico")!)
        let (body, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/callback?code=AQB&state=s1")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: body, as: UTF8.self).contains("connected"))
        #expect(await waiting.value == "AQB")
    }

    @Test func forgedOrSilentRequestsDoNotCancel() async throws {
        let port: UInt16 = 47_898
        let waiting = Task.detached { SpotifyAPI.waitForCallback(state: "s1", port: port, timeout: 8) }
        try await Task.sleep(for: .milliseconds(200))
        // A connection that never sends anything, then a page trying a forged state, then the real redirect.
        let silent = socket(AF_INET, SOCK_STREAM, 0)
        var addr = sockaddr_in(); addr.sin_family = sa_family_t(AF_INET); addr.sin_port = port.bigEndian; addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(silent, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        defer { close(silent) }
        _ = try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/callback?code=EVIL&state=forged")!)
        _ = try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/callback?code=AQB&state=s1")!)
        #expect(await waiting.value == "AQB")
    }
}
