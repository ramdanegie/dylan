import Foundation
import Testing
@testable import DylanCore

@Suite struct BridgeTests {
    @Test(arguments: [
        BridgeMessage.activityStart(id: "deploy", title: "Deploy staging", subtitle: nil, progress: 0, url: nil),
        .activityUpdate(id: "deploy", title: nil, subtitle: "migrasi DB", progress: 0.6),
        .activityEnd(id: "deploy", success: true, detail: "v2.4.1 · 3m 10s"),
        .notify(title: "Backup selesai", body: "12 GB"),
        .shellStart(shellPid: 123, cmd: "npm test", cwd: "/Users/gg/api", app: "com.microsoft.VSCode", seq: 4),
        .shellStart(shellPid: 123, cmd: "npm test", cwd: "/Users/gg/api", app: nil, seq: nil),
        .shellEnd(shellPid: 123, status: 1, seq: 4),
        .hook(source: "claude", env: ["TERM_PROGRAM": "vscode"], payload: .object(["session_id": .string("s")])),
        .permissionAsk(requestId: "r1", source: "claude", env: [:], payload: .object(["n": .number(1)])),
        .shelfAdd(paths: ["/tmp/a.png"]),
        .ping, .debugState,
    ])
    func roundTrip(_ m: BridgeMessage) throws {
        let line = try m.encodedLine()
        #expect(line.last == 0x0A)
        #expect(!line.dropLast().contains(0x0A))
        #expect(try BridgeMessage.decode(line: line.dropLast()) == m)
    }

    @Test func decodesPRDExamples() throws {
        let lines = [
            #"{"v":1,"type":"activity.start","id":"deploy","kind":"script","title":"Deploy staging","progress":0}"#,
            #"{"v":1,"type":"activity.end","id":"deploy","result":"success","detail":"v2.4.1 · 3m 10s"}"#,
            #"{"v":1,"type":"shell.end","shellPid":123,"status":1}"#,
        ]
        for l in lines { _ = try BridgeMessage.decode(line: Data(l.utf8)) }
    }

    @Test func rejectsBadInput() {
        #expect(throws: BridgeError.unsupportedVersion(2)) {
            try BridgeMessage.decode(line: Data(#"{"v":2,"type":"ping"}"#.utf8))
        }
        #expect(throws: BridgeError.unknownType("rm")) {
            try BridgeMessage.decode(line: Data(#"{"v":1,"type":"rm"}"#.utf8))
        }
        #expect(throws: BridgeError.invalid("result")) {
            try BridgeMessage.decode(line: Data(#"{"v":1,"type":"activity.end","id":"x","result":"maybe"}"#.utf8))
        }
        #expect(throws: BridgeError.tooLarge) {
            try BridgeMessage.decode(line: Data(repeating: 0x20, count: Bridge.maxMessageBytes + 1))
        }
    }

    @Test func progressIsClampedAtDecode() throws {
        let big = try BridgeMessage.decode(line: Data(#"{"v":1,"type":"activity.update","id":"x","progress":1e300}"#.utf8))
        #expect(big == .activityUpdate(id: "x", title: nil, subtitle: nil, progress: 1))
        let neg = try BridgeMessage.decode(line: Data(#"{"v":1,"type":"activity.start","id":"x","title":"t","progress":-3}"#.utf8))
        #expect(neg == .activityStart(id: "x", title: "t", subtitle: nil, progress: 0, url: nil))
    }

    @Test func lineBufferSplitsAndLimits() throws {
        var b = LineBuffer()
        #expect(try b.append(Data("{\"a\":1}\n{\"b\"".utf8)).count == 1)
        #expect(try b.append(Data(":2}\n\n".utf8)) == [Data("{\"b\":2}".utf8)])
        #expect(throws: BridgeError.tooLarge) { try b.append(Data(repeating: 0x41, count: Bridge.maxMessageBytes + 1)) }
    }

    @Test func jsonValueKeepsTypes() throws {
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a":true,"b":1,"c":"x","d":null,"e":[1]}"#.utf8))
        #expect(v["a"]?.bool == true)
        #expect(v["b"]?.number == 1)
        #expect(v["c"]?.string == "x")
        #expect(v["d"] == .null)
    }

    @Test func permissionOutput() throws {
        #expect(HookOutput.permissionRequest(PermissionReply(decision: .passthrough)) == nil)
        let allow = try #require(HookOutput.permissionRequest(PermissionReply(decision: .allow)))
        #expect(String(decoding: allow, as: UTF8.self) ==
                #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#)
        let deny = try #require(HookOutput.permissionRequest(PermissionReply(decision: .deny, message: "no")))
        #expect(String(decoding: deny, as: UTF8.self).contains(#""behavior":"deny","message":"no""#))
    }

    @Test func shellInitQuotesPathAndRunsInBackground() {
        let s = ShellInit.zsh(cliPath: "/Applications/My Apps/Dylan.app/Contents/MacOS/dylan")
        #expect(s.contains(#"print -rn -- "$1" | '/Applications/My Apps/Dylan.app/Contents/MacOS/dylan' _shell start"#))
        #expect(!s.contains("--cmd"))   // command text stays out of argv (visible in ps)
        #expect(s.contains("--seq $_dylan_seq"))
        #expect(s.components(separatedBy: "&!").count == 3)
        #expect(s.contains("add-zsh-hook preexec _dylan_preexec"))
    }

    @Test func discordFrames() throws {
        let f = DiscordFrame.handshake(clientID: "1290")
        let bytes = f.encoded
        #expect(Array(bytes.prefix(4)) == [0, 0, 0, 0])
        var d = DiscordFrame.Decoder()
        // Split mid-header and mid-payload, plus a second frame in the same chunk.
        let two = bytes + DiscordFrame(opcode: .frame, json: Data("{}".utf8)).encoded
        #expect(try d.append(two.prefix(5)).isEmpty)
        #expect(try d.append(two.dropFirst(5).prefix(10)).isEmpty)
        let frames = try d.append(two.dropFirst(15))
        #expect(frames.count == 2)
        #expect(frames[0] == f)
        #expect(frames[1].opcode == .frame)
        let obj = try JSONSerialization.jsonObject(with: frames[0].json) as? [String: Any]
        #expect(obj?["client_id"] as? String == "1290")
        var bad = DiscordFrame.Decoder()
        #expect(throws: DiscordFrame.DecodeError.badOpcode(9)) { try bad.append(Data([9, 0, 0, 0, 0, 0, 0, 0])) }
    }
}

@Suite struct SocketTests {
    @Test func roundTripOverUnixSocket() throws {
        let path = "/tmp/dylan-test-\(UUID().uuidString.prefix(8)).sock"
        let server = try UnixSocket.listen(path: path)
        defer { close(server); unlink(path) }
        var st = stat()
        #expect(stat(path, &st) == 0 && (st.st_mode & 0o777) == 0o600)

        let client = try UnixSocket.connect(path: path, timeout: 1)
        defer { close(client) }
        let conn = accept(server, nil, nil)
        defer { close(conn) }
        #expect(UnixSocket.peerIsSameUser(conn))
        UnixSocket.setTimeouts(conn, 1)

        try UnixSocket.write(client, try BridgeMessage.ping.encodedLine())
        #expect(try BridgeMessage.decode(line: try UnixSocket.readLine(conn)) == .ping)
        try UnixSocket.write(conn, Data(#"{"decision":"allow"}"#.utf8 + [0x0A]))
        #expect(try JSONDecoder().decode(PermissionReply.self, from: try UnixSocket.readLine(client)).decision == .allow)
    }

    @Test func connectFailsFastWhenNoServer() {
        let start = Date()
        #expect(throws: (any Error).self) { try UnixSocket.connect(path: "/tmp/dylan-none-\(UUID().uuidString.prefix(6)).sock", timeout: 0.2) }
        #expect(Date().timeIntervalSince(start) < 0.1)
    }
}
