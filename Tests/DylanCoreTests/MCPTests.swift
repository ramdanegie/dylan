import Foundation
import Testing
@testable import DylanCore

@Suite struct MCPTests {
    final class Box: @unchecked Sendable { var sent: [BridgeMessage] = [] }

    func reply(_ s: MCPServer, _ json: String) throws -> [String: Any] {
        let out = try #require(s.handle(Data(json.utf8)))
        return try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])
    }

    @Test func handshakeAndTools() throws {
        let box = Box()
        let s = MCPServer(version: "0.1.0") { box.sent.append($0); return true }
        let i = try reply(s, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#)
        #expect(((i["result"] as? [String: Any])?["serverInfo"] as? [String: Any])?["name"] as? String == "dylan")
        #expect(s.handle(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)) == nil)
        let l = try reply(s, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let names = ((l["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        #expect(names == ["notify", "activity", "shelf_add"])
    }

    @Test func toolsBecomeBridgeMessages() throws {
        let box = Box()
        let s = MCPServer(version: "0.1.0") { box.sent.append($0); return true }
        _ = try reply(s, #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"notify","arguments":{"title":"Tests lulus","body":"128"}}}"#)
        _ = try reply(s, #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"activity","arguments":{"id":"mig","state":"start","title":"Migrasi","progress":7}}}"#)
        _ = try reply(s, #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"activity","arguments":{"id":"mig","state":"success","detail":"3m"}}}"#)
        _ = try reply(s, #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"shelf_add","arguments":{"paths":["/tmp/a.png"]}}}"#)
        #expect(box.sent == [.notify(title: "Tests lulus", body: "128"),
                             .activityStart(id: "mcp-mig", title: "Migrasi", subtitle: nil, progress: 1, url: nil),
                             .activityEnd(id: "mcp-mig", success: true, detail: "3m"),
                             .shelfAdd(paths: ["/tmp/a.png"])])
    }

    @Test func errors() throws {
        let s = MCPServer(version: "0.1.0") { _ in false }
        let bad = try reply(s, #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"notify","arguments":{}}}"#)
        #expect((bad["result"] as? [String: Any])?["isError"] as? Bool == true)
        let down = try reply(s, #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"notify","arguments":{"title":"x"}}}"#)
        #expect((((down["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String) == "Dylan is not running")
        let unknown = try reply(s, #"{"jsonrpc":"2.0","id":9,"method":"resources/list"}"#)
        #expect((unknown["error"] as? [String: Any])?["code"] as? Int == -32601)
        let parse = try reply(s, "{nope")
        #expect((parse["error"] as? [String: Any])?["code"] as? Int == -32700)
    }
}

@Suite struct CodexConfigTests {
    let cli = "/Applications/Dylan.app/Contents/Helpers/dylan"

    @Test func installReplaceUninstall() {
        let user = "model = \"o4\"\n\n[profiles.fast]\nnotify = [\"other\"]\n"
        let a = CodexConfig.install(user, cliPath: cli)
        #expect(a.hasPrefix("notify = [\"\(cli)\", \"hook\", \"codex\"]\n"))
        #expect(a.contains("[profiles.fast]\nnotify = [\"other\"]"))   // table-level notify untouched
        #expect(CodexConfig.isInstalled(a))
        #expect(CodexConfig.install(a, cliPath: cli) == a)               // idempotent
        #expect(CodexConfig.uninstall(a) == user)
        let theirs = "notify = [\"terminal-notifier\"]\nmodel = \"o4\"\n"
        #expect(!CodexConfig.isInstalled(theirs))
        #expect(CodexConfig.uninstall(theirs) == theirs)                  // never removes someone else's notify
        #expect(CodexConfig.install(theirs, cliPath: cli).hasPrefix("notify = [\"\(cli)\""))
    }

    @Test func lastMessage() throws {
        let j = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"type":"agent-turn-complete","turn-id":"1","last-assistant-message":"Done. Tests pass."}"#.utf8))
        #expect(CodexConfig.lastMessage(j) == "Done. Tests pass.")
        #expect(CodexConfig.lastMessage(.object(["type": .string("other")])) == nil)
    }
}
