import Foundation
import Testing
@testable import DylanCore

@Suite struct AgentAdapterTests {
    func json(_ s: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }

    @Test func cursorSessionThroughTheClaudePipeline() throws {
        var sessions = AgentSessions()
        let t0 = Date(timeIntervalSince1970: 1_000)
        func feed(_ s: String, _ at: TimeInterval) throws {
            let p = try #require(AgentAdapter.cursor(try json(s)))
            let e = try #require(ClaudeHookEvent(payload: HookPayload.slim(p)))
            sessions.apply(e, env: [:], now: t0.addingTimeInterval(at)) { ($0 as NSString).lastPathComponent }
        }
        let base = #""conversation_id":"c1","workspace_roots":["/w/web-admin"]"#
        try feed(#"{"hook_event_name":"sessionStart",\#(base)}"#, 0)
        try feed(#"{"hook_event_name":"postToolUse",\#(base),"tool_name":"Shell","tool_input":{"command":"npm test"}}"#, 5)
        let s = try #require(sessions.sessions["cursor-c1"])
        #expect(s.agent == "Cursor" && s.project == "web-admin")
        #expect(s.status == .working(tool: "Bash", detail: "npm test"))
        try feed(#"{"hook_event_name":"afterFileEdit",\#(base),"file_path":"/w/web-admin/a.ts","edits":[]}"#, 8)
        #expect(sessions.sessions["cursor-c1"]?.changedFiles == ["/w/web-admin/a.ts"])
        try feed(#"{"hook_event_name":"stop",\#(base),"status":"completed"}"#, 20)
        #expect(sessions.sessions["cursor-c1"]?.status == .done(duration: 15, summary: nil))   // from the first tool
    }

    @Test func cursorEdgeCases() throws {
        #expect(AgentAdapter.cursor(try json(#"{"hook_event_name":"stop","workspace_roots":[]}"#)) == nil)          // no conversation
        #expect(AgentAdapter.cursor(try json(#"{"hook_event_name":"beforeReadFile","conversation_id":"c"}"#)) == nil) // not observed
        let fail = try #require(AgentAdapter.cursor(try json(#"{"hook_event_name":"stop","conversation_id":"c","status":"error"}"#)))
        #expect(fail["hook_event_name"]?.string == "StopFailure")
        #expect(AgentAdapter.cursorOutput(event: "beforeSubmitPrompt") == #"{"continue":true}"#)
        #expect(AgentAdapter.cursorOutput(event: "stop") == "{}")
        #expect(!AgentAdapter.cursorEvents.contains { $0.hasPrefix("before") || $0 == "preToolUse" })
    }

    @Test func opencodeEvents() throws {
        let busy = try #require(AgentAdapter.opencode(try json(#"{"type":"session.status","sessionID":"s","status":"busy","cwd":"/w/api"}"#)))
        #expect(busy["hook_event_name"]?.string == "PreToolUse" && busy["session_id"]?.string == "opencode-s")
        #expect(AgentAdapter.opencode(try json(#"{"type":"session.status","sessionID":"s","status":"idle"}"#)) == nil)
        let tool = try #require(AgentAdapter.opencode(try json(#"{"type":"tool","sessionID":"s","tool":"bash","command":"go test ./..."}"#)))
        #expect(tool["tool_name"]?.string == "Bash" && tool["tool_input"]?["command"]?.string == "go test ./...")
        #expect(AgentAdapter.opencode(try json(#"{"type":"permission.asked","sessionID":"s"}"#))?["notification_type"]?.string == "permission_prompt")
        #expect(AgentAdapter.opencode(try json(#"{"type":"session.idle","sessionID":"s"}"#))?["hook_event_name"]?.string == "Stop")
        #expect(AgentAdapter.opencode(try json(#"{"type":"session.idle"}"#)) == nil)
    }

    @Test func cursorInstallerKeepsUserHooks() throws {
        let cmd = AgentAdapter.cursorCommand(cliPath: "/Applications/Dylan.app/Contents/Helpers/dylan")
        let user = Data(#"{"version":1,"hooks":{"stop":[{"command":"./audit.sh"}],"beforeShellExecution":[{"command":"./guard.sh"}],"beforeSubmitPrompt":[{"command":"'/old/dylan' hook cursor"}]}}"#.utf8)
        let once = try AgentAdapter.installCursor(user, command: cmd)
        let twice = try AgentAdapter.installCursor(once, command: cmd)
        #expect(once == twice)
        #expect(AgentAdapter.cursorInstalled(once))
        let root = try #require(JSONSerialization.jsonObject(with: once) as? [String: Any])
        let hooks = try #require(root["hooks"] as? [String: [[String: Any]]])
        #expect(hooks["stop"]?.count == 2 && hooks["beforeShellExecution"]?.count == 1)
        #expect(hooks["beforeSubmitPrompt"] == nil)   // an older Dylan entry on a gating hook is removed
        let removed = try AgentAdapter.uninstallCursor(once)
        #expect(!AgentAdapter.cursorInstalled(removed))
        let back = try #require((JSONSerialization.jsonObject(with: removed) as? [String: Any])?["hooks"] as? [String: [[String: Any]]])
        #expect(back["stop"]?.count == 1 && back["sessionStart"] == nil)
        #expect(throws: (any Error).self) { try AgentAdapter.installCursor(Data("[1]".utf8), command: cmd) }
    }

    @Test func toolNames() {
        #expect(AgentAdapter.toolName("run_terminal_cmd") == "Bash")
        #expect(AgentAdapter.toolName("read") == "Read")
        #expect(AgentAdapter.toolName("webfetch") == "Webfetch")
        #expect(AgentAdapter.toolName(nil) == "Tool")
    }
}
