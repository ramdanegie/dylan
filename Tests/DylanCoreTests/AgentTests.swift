import Foundation
import Testing
@testable import DylanCore

private func fixture(_ name: String) throws -> JSONValue {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/claude"))
    return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
}

private let t0 = Date(timeIntervalSince1970: 2_000_000)
private let env = ["__CFBundleIdentifier": "com.microsoft.VSCode", "TERM_PROGRAM": "vscode"]

@Suite struct AgentTests {
    @Test func parsesAllFixtures() throws {
        for n in ["SessionStart", "UserPromptSubmit", "PreToolUse-Edit", "PreToolUse-Bash", "PostToolUse-Edit",
                  "Notification-permission", "Notification-idle", "PermissionRequest", "Stop", "SessionEnd"] {
            #expect(ClaudeHookEvent(payload: try fixture(n)) != nil, "\(n)")
        }
    }

    @Test func toolDetails() throws {
        #expect(ClaudeHookEvent(payload: try fixture("PreToolUse-Edit"))?.toolDetail == "AuthService.swift")
        #expect(ClaudeHookEvent(payload: try fixture("PreToolUse-Bash"))?.toolDetail == "npm test")
        let long = JSONValue.object(["hook_event_name": .string("PreToolUse"), "session_id": .string("s"),
                                     "tool_name": .string("Bash"), "tool_input": .object(["command": .string(String(repeating: "x", count: 100) + "\nmore")])])
        #expect(ClaudeHookEvent(payload: long)?.toolDetail?.count == 60)
    }

    @Test func ignoresUnknownEventsAndMissingSession() {
        #expect(ClaudeHookEvent(payload: .object(["hook_event_name": .string("PreCompact"), "session_id": .string("s")])) == nil)
        #expect(ClaudeHookEvent(payload: .object(["hook_event_name": .string("Stop")])) == nil)
        #expect(ClaudeHookEvent(payload: .string("garbage")) == nil)
    }

    @Test func fullSessionLifecycle() throws {
        var s = AgentSessions()
        func apply(_ n: String, _ t: TimeInterval) throws {
            s.apply(try #require(ClaudeHookEvent(payload: try fixture(n))), env: env, now: t0.addingTimeInterval(t),
                    projectName: { ($0 as NSString).lastPathComponent })
        }
        try apply("SessionStart", 0)
        #expect(s.sessions["abc123"]?.project == "api-gateway")
        #expect(s.sessions["abc123"]?.appBundleID == "com.microsoft.VSCode")
        #expect(s.active.isEmpty)

        try apply("UserPromptSubmit", 10)
        try apply("PreToolUse-Edit", 20)
        #expect(s.sessions["abc123"]?.status == .working(tool: "Edit", detail: "AuthService.swift"))
        try apply("PostToolUse-Edit", 21)
        #expect(s.sessions["abc123"]?.changedFiles == ["/Users/gg/dev/api-gateway/Sources/AuthService.swift"])

        try apply("PermissionRequest", 30)
        #expect(s.permissionCount == 1)
        try apply("Notification-permission", 31)
        #expect(s.sessions["abc123"]?.status == .needsPermission(requestID: nil, tool: "Bash", detail: "npm install zod"))

        try apply("Stop", 262)
        #expect(s.sessions["abc123"]?.status == .done(duration: 252, summary: "Menambahkan refresh token di AuthService beserta test-nya."))
        try apply("Notification-idle", 263)
        if case .done = s.sessions["abc123"]?.status {} else { Issue.record("idle after Stop must not hide the result") }
        s.acknowledgeResult(sessionID: "abc123")
        #expect(s.sessions["abc123"]?.status == .idle)

        try apply("SessionEnd", 300)
        #expect(s.sessions.isEmpty)
    }

    @Test func staleSessionsExpire() throws {
        var s = AgentSessions()
        s.apply(try #require(ClaudeHookEvent(payload: try fixture("PreToolUse-Bash"))), env: [:], now: t0, projectName: { _ in "p" })
        #expect(s.expireStale(now: t0.addingTimeInterval(3600)).isEmpty)
        #expect(s.expireStale(now: t0.addingTimeInterval(7200)) == ["abc123"])
        #expect(s.sessions.isEmpty)
    }

    @Test func eventBeforeSessionStartCreatesSession() throws {
        var s = AgentSessions()
        s.apply(try #require(ClaudeHookEvent(payload: try fixture("PreToolUse-Bash"))), env: [:], now: t0, projectName: { _ in "p" })
        #expect(s.sessions["abc123"]?.promptStartedAt == t0)
    }

    @Test func notchPermissionLifecycle() throws {
        var s = AgentSessions()
        s.apply(try #require(ClaudeHookEvent(payload: try fixture("UserPromptSubmit"))), env: env, now: t0, projectName: { _ in "p" })
        s.setPermission(sessionID: "abc123", requestID: "r1", tool: "Bash", detail: "npm install zod", now: t0)
        #expect(s.permissionCount == 1)
        s.clearPermission(requestID: "r1", now: t0)
        #expect(s.sessions["abc123"]?.status == .working(tool: "Bash", detail: "npm install zod"))
    }

    @Test func projectNameUsesGitRoot() {
        let existing: Set<String> = ["/Users/gg/dev/api-gateway/.git"]
        #expect(ProjectName.resolve(cwd: "/Users/gg/dev/api-gateway/Sources/Auth", exists: existing.contains) == "api-gateway")
        #expect(ProjectName.resolve(cwd: "/tmp/scratch", exists: existing.contains) == "scratch")
    }

    @Test func shortStat() {
        #expect(ShortStat.parse(" 3 files changed, 120 insertions(+), 8 deletions(-)\n")! == (120, 8))
        #expect(ShortStat.parse(" 1 file changed, 1 insertion(+)")! == (1, 0))
        #expect(ShortStat.parse(" 2 files changed, 4 deletions(-)")! == (0, 4))
        #expect(ShortStat.parse("") == nil)
    }
}

@Suite struct HookPayloadTests {
    @Test func slimDropsFileContents() throws {
        let big = String(repeating: "x", count: 200_000)
        let p = JSONValue.object([
            "hook_event_name": .string("PreToolUse"), "session_id": .string("s"), "tool_name": .string("Write"),
            "transcript_path": .string("/x.jsonl"),
            "tool_input": .object(["file_path": .string("/a/b.swift"), "content": .string(big)]),
            "tool_response": .object(["content": .string(big)]),
            "last_assistant_message": .string(big),
        ])
        let slim = HookPayload.slim(p)
        #expect(slim["tool_input"]?["content"] == nil)
        #expect(slim["tool_input"]?["file_path"]?.string == "/a/b.swift")
        #expect(slim["tool_response"] == nil && slim["transcript_path"] == nil)
        #expect(slim["last_assistant_message"]?.string?.count == 2000)
        let line = try BridgeMessage.hook(source: "claude", env: [:], payload: slim).encodedLine()
        #expect(line.count < Bridge.maxMessageBytes)
        #expect(ClaudeHookEvent(payload: slim)?.toolName == "Write")
    }
}
