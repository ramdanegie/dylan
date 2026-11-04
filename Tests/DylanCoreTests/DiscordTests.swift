import Foundation
import Testing
@testable import DylanCore

private func json(_ s: String) -> [String: Any] { try! JSONSerialization.jsonObject(with: Data(s.utf8)) as! [String: Any] }

@Suite struct DiscordStateTests {
    @Test func readyToVoice() {
        var s = DiscordState()
        #expect(s.apply(json(#"{"cmd":"DISPATCH","evt":"READY","data":{"v":1,"user":{"id":"me"}}}"#)) == .needsAuthorize)
        #expect(s.apply(json(#"{"cmd":"AUTHORIZE","data":{"code":"abc"}}"#)) == .exchangeCode("abc"))
        #expect(s.apply(json(#"{"cmd":"AUTHENTICATE","data":{"user":{"id":"me"}}}"#)) == .none)
        #expect(s.authenticated)
        let sel = json(#"""
        {"cmd":"GET_SELECTED_VOICE_CHANNEL","data":{"id":"c1","name":"ngoding","voice_states":[
          {"nick":"Raka","user":{"id":"r","username":"raka","avatar":"h1"},"voice_state":{"mute":false,"self_mute":false}},
          {"user":{"id":"me","username":"egie"},"voice_state":{"self_mute":true,"self_deaf":false}}]}}
        """#)
        #expect(s.apply(sel) == .subscribeChannel("c1", previous: nil))
        #expect(s.inVoice && s.channelName == "ngoding" && s.members.count == 2)
        #expect(s.selfMute && !s.selfDeaf)
        #expect(s.members[0].avatarURL == "https://cdn.discordapp.com/avatars/r/h1.png?size=64")
    }

    @Test func speakingOrderAndLeave() {
        var s = DiscordState()
        _ = s.apply(json(#"{"cmd":"GET_SELECTED_VOICE_CHANNEL","data":{"id":"c1","name":"x","voice_states":[{"user":{"id":"a","username":"a"}},{"user":{"id":"b","username":"b"}}]}}"#))
        _ = s.apply(json(#"{"cmd":"DISPATCH","evt":"SPEAKING_START","data":{"user_id":"a"}}"#))
        _ = s.apply(json(#"{"cmd":"DISPATCH","evt":"SPEAKING_START","data":{"user_id":"b"}}"#))
        #expect(s.speakers.map(\.id) == ["b", "a"])          // newest speaker first (design M9)
        _ = s.apply(json(#"{"cmd":"DISPATCH","evt":"SPEAKING_STOP","data":{"user_id":"b"}}"#))
        #expect(s.speakers.map(\.id) == ["a"])
        _ = s.apply(json(#"{"cmd":"DISPATCH","evt":"VOICE_STATE_DELETE","data":{"user":{"id":"a"}}}"#))
        #expect(s.members.map(\.id) == ["b"] && s.speakers.isEmpty)
        #expect(s.apply(json(#"{"cmd":"DISPATCH","evt":"VOICE_CHANNEL_SELECT","data":{"channel_id":null}}"#)) == .subscribeChannel("", previous: "c1"))
        #expect(!s.inVoice && s.members.isEmpty)
    }

    @Test func voiceSettingsAndMessages() {
        var s = DiscordState()
        _ = s.apply(json(#"{"cmd":"DISPATCH","evt":"VOICE_SETTINGS_UPDATE","data":{"mute":true,"deaf":true}}"#))
        #expect(s.selfMute && s.selfDeaf)
        let e = s.apply(json(##"{"cmd":"DISPATCH","evt":"NOTIFICATION_CREATE","data":{"channel_id":"42","title":"#tugas-akhir","body":"ada yang mau review slide?","message":{"author":{"username":"Raka"}}}}"##))
        guard case .message(let m) = e else { Issue.record("no message"); return }
        #expect(m.author == "Raka" && m.channel == "#tugas-akhir")
        #expect(DiscordState.deepLink(m)?.absoluteString == "discord://-/channels/@me/42")
        _ = s.apply(json(#"{"cmd":"AUTHORIZE","evt":"ERROR","data":{"code":5000,"message":"OAuth2 Error"}}"#))
        #expect(s.lastError == "OAuth2 Error")
    }

    @Test func commands() throws {
        let a = try #require(try JSONSerialization.jsonObject(with: DiscordRPC.authorize(clientID: "129")) as? [String: Any])
        #expect(a["cmd"] as? String == "AUTHORIZE")
        #expect(((a["args"] as? [String: Any])?["scopes"] as? [String]) == DiscordRPC.scopes)
        let leave = try #require(try JSONSerialization.jsonObject(with: DiscordRPC.leaveVoice()) as? [String: Any])
        #expect((leave["args"] as? [String: Any])?["channel_id"] is NSNull)
        #expect(DiscordRPC.tokenRequestBody(clientID: "1", clientSecret: "s&x", code: "c=1") == "client_id=1&grant_type=authorization_code&code=c%3D1&client_secret=s%26x")
        #expect(DiscordRPC.socketPaths(tmpdir: "/tmp/").first == "/tmp/discord-ipc-0")
    }
}

/// End to end over a real unix socket with a fake Discord: handshake → READY → AUTHORIZE.
@Suite struct DiscordIPCTests {
    @Test func handshakeOverSocket() throws {
        let path = "/tmp/dylan-discord-\(UUID().uuidString.prefix(6))"
        let server = try UnixSocket.listen(path: path)
        defer { close(server); unlink(path) }
        let client = try UnixSocket.connect(path: path, timeout: 1)
        defer { close(client) }
        let conn = accept(server, nil, nil)
        defer { close(conn) }
        UnixSocket.setTimeouts(conn, 1)

        try UnixSocket.write(client, DiscordFrame.handshake(clientID: "129").encoded)
        var dec = DiscordFrame.Decoder()
        var buf = [UInt8](repeating: 0, count: 512)
        let n = read(conn, &buf, buf.count)
        let frames = try dec.append(Data(buf[0..<n]))
        #expect(frames.first?.opcode == .handshake)
        // Fake Discord answers READY.
        try UnixSocket.write(conn, DiscordFrame(opcode: .frame, json: Data(#"{"cmd":"DISPATCH","evt":"READY","data":{"user":{"id":"me"}}}"#.utf8)).encoded)
        UnixSocket.setTimeouts(client, 1)
        var cdec = DiscordFrame.Decoder()
        let m = read(client, &buf, buf.count)
        let reply = try #require(try cdec.append(Data(buf[0..<m])).first)
        var state = DiscordState()
        #expect(state.apply(try JSONSerialization.jsonObject(with: reply.json) as! [String: Any]) == .needsAuthorize)
    }
}
