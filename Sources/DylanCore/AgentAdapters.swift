import Foundation

/// Other coding agents through the Claude Code pipeline (FR-34): each event is translated into the
/// Claude hook shape (`hook_event_name`, `session_id`, `cwd`, `tool_name`, `tool_input`) plus `dylan_agent`.
/// Observation only: Dylan never answers another agent's permission prompt.
public enum AgentAdapter {
    // MARK: Cursor (~/.cursor/hooks.json)

    /// Hooks whose output Cursor does not read as a decision. Every before*/preToolUse hook is left out on
    /// purpose (beforeSubmitPrompt included: its `continue` gates the prompt): Cursor blocks on output it cannot
    /// parse, a moved app would then break every prompt, and Dylan must never approve anything.
    public static let cursorEvents = ["sessionStart", "postToolUse", "afterFileEdit", "stop", "sessionEnd"]

    /// What `dylan hook cursor` prints, Dylan running or not. beforeSubmitPrompt is not installed any more;
    /// an older install still gets a valid answer.
    public static func cursorOutput(event: String?) -> String {
        event == "beforeSubmitPrompt" ? #"{"continue":true}"# : "{}"
    }

    public static func cursor(_ p: JSONValue) -> JSONValue? {
        guard let event = p["hook_event_name"]?.string,
              let conv = (p["conversation_id"]?.string ?? p["session_id"]?.string), !conv.isEmpty else { return nil }
        var o: [String: JSONValue] = ["session_id": .string("cursor-" + conv), "dylan_agent": .string("Cursor")]
        if case .array(let roots)? = p["workspace_roots"], let first = roots.first?.string { o["cwd"] = .string(first) }
        switch event {
        case "sessionStart": o["hook_event_name"] = .string("SessionStart")
        case "beforeSubmitPrompt": o["hook_event_name"] = .string("UserPromptSubmit")
        case "postToolUse":
            o["hook_event_name"] = .string("PreToolUse")   // "now using X": Cursor has no observe-only pre hook
            o["tool_name"] = .string(toolName(p["tool_name"]?.string))
            o["tool_input"] = p["tool_input"]
        case "afterFileEdit":
            o["hook_event_name"] = .string("PostToolUse")
            o["tool_name"] = .string("Edit")
            if let f = p["file_path"]?.string { o["tool_input"] = .object(["file_path": .string(f)]) }
        case "stop":
            o["hook_event_name"] = .string(p["status"]?.string == "error" ? "StopFailure" : "Stop")
        case "sessionEnd": o["hook_event_name"] = .string("SessionEnd")
        default: return nil
        }
        return .object(o)
    }

    // MARK: OpenCode (~/.config/opencode/plugins/dylan.js)

    /// The plugin sends `{type, sessionID, cwd, status?, tool?, command?, filePath?, error?}`.
    public static func opencode(_ p: JSONValue) -> JSONValue? {
        guard let type = p["type"]?.string, let sid = p["sessionID"]?.string, !sid.isEmpty else { return nil }
        var o: [String: JSONValue] = ["session_id": .string("opencode-" + sid), "dylan_agent": .string("OpenCode")]
        if let cwd = p["cwd"]?.string { o["cwd"] = .string(cwd) }
        switch type {
        case "session.status":
            guard p["status"]?.string == "busy" else { return nil }
            o["hook_event_name"] = .string("PreToolUse")   // keeps the prompt start time across repeated busy events
        case "tool":
            o["hook_event_name"] = .string("PreToolUse")
            o["tool_name"] = .string(toolName(p["tool"]?.string))
            var input: [String: JSONValue] = [:]
            if let c = p["command"]?.string { input["command"] = .string(c) }
            if let f = p["filePath"]?.string { input["file_path"] = .string(f) }
            o["tool_input"] = .object(input)
        case "permission.asked":
            o["hook_event_name"] = .string("Notification")
            o["notification_type"] = .string("permission_prompt")
        case "permission.replied": o["hook_event_name"] = .string("PreToolUse")
        case "session.idle": o["hook_event_name"] = .string("Stop")
        case "session.error":
            o["hook_event_name"] = .string("StopFailure")
            if let e = p["error"]?.string { o["message"] = .string(e) }
        case "session.deleted": o["hook_event_name"] = .string("SessionEnd")
        default: return nil
        }
        return .object(o)
    }

    /// Tool names onto the ones Dylan describes ("Bash", "Edit", "Read", …).
    static func toolName(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Tool" }
        switch raw.lowercased() {
        case "shell", "bash", "run_terminal_cmd", "terminal": return "Bash"
        case "edit", "edit_file", "str_replace", "search_replace", "multiedit", "patch": return "Edit"
        case "write", "create_file": return "Write"
        case "read", "read_file": return "Read"
        case "grep", "codebase_search", "search": return "Grep"
        case "glob", "list", "list_dir", "file_search": return "Glob"
        default: return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    // MARK: Installers

    /// Adds `dylan hook cursor` for each event to hooks.json, keeping the user's own hooks. Idempotent.
    public static func installCursor(_ old: Data?, command: String) throws -> Data {
        // Start from a clean slate so Dylan entries on events it no longer uses go away.
        var root = try cursorRoot(old.map(uninstallCursor) ?? nil)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for e in cursorEvents {
            var list = (hooks[e] as? [[String: Any]] ?? []).filter { !isDylan($0["command"] as? String) }
            list.append(["command": command])
            hooks[e] = list
        }
        root["hooks"] = hooks
        if root["version"] == nil { root["version"] = 1 }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    public static func uninstallCursor(_ old: Data) throws -> Data {
        var root = try cursorRoot(old)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for (e, v) in hooks {
            guard let list = v as? [[String: Any]] else { continue }
            let kept = list.filter { !isDylan($0["command"] as? String) }
            if kept.isEmpty && list.count != kept.count { hooks[e] = nil } else { hooks[e] = kept }
        }
        root["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    public static func cursorInstalled(_ data: Data?) -> Bool {
        guard let data, let root = try? cursorRoot(data), let hooks = root["hooks"] as? [String: Any] else { return false }
        return cursorEvents.allSatisfy { e in (hooks[e] as? [[String: Any]] ?? []).contains { isDylan($0["command"] as? String) } }
    }

    public static func cursorRootIsValid(_ data: Data?) throws -> Bool { _ = try cursorRoot(data); return true }

    static func cursorRoot(_ data: Data?) throws -> [String: Any] {
        guard let data, !data.isEmpty else { return [:] }
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        return o
    }

    static func isDylan(_ command: String?) -> Bool {
        command?.range(of: #"(^|/)dylan(-cli)?'?\s+hook\s+cursor\b"#, options: .regularExpression) != nil
    }

    public static func cursorCommand(cliPath: String) -> String {
        "'" + cliPath.replacingOccurrences(of: "'", with: "'\\''") + "' hook cursor"
    }

    /// The OpenCode plugin. Fire-and-forget: it never awaits Dylan and ignores every error.
    public static func opencodePlugin(cliPath: String) -> String {
        let path = String(data: try! JSONSerialization.data(withJSONObject: [cliPath], options: [.withoutEscapingSlashes]), encoding: .utf8)!
        return """
        // Dylan notch (https://github.com/ramdanegie/dylan): shows OpenCode sessions in the notch.
        // Observation only; remove this file to turn it off.
        const DYLAN = \(path)[0]

        export const DylanNotch = async ({ directory }) => {
          const send = (payload) => {
            try {
              const p = Bun.spawn([DYLAN, "hook", "opencode"], { stdin: "pipe", stdout: "ignore", stderr: "ignore" })
              p.stdin.write(JSON.stringify({ ...payload, cwd: directory }))
              p.stdin.end()
            } catch {}
          }
          return {
            event: async ({ event }) => {
              const props = event.properties ?? {}
              const sessionID = props.sessionID ?? props.info?.id
              if (["session.status", "session.idle", "session.error", "session.deleted", "permission.asked", "permission.replied"].includes(event.type)) {
                send({ type: event.type, sessionID, status: props.status?.type, error: props.error?.name })
              }
            },
            "tool.execute.before": async (input, output) => {
              send({ type: "tool", sessionID: input.sessionID, tool: input.tool, command: output?.args?.command, filePath: output?.args?.filePath })
            },
          }
        }

        """
    }
}
