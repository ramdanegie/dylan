import Foundation

/// Minimal MCP server over stdio (FR-42): `dylan mcp`. JSON-RPC 2.0, one message per line.
/// Tools turn into the same bridge messages as the CLI, so Claude Code can post to the notch.
public struct MCPServer {
    public let version: String
    public let send: (BridgeMessage) -> Bool
    public init(version: String, send: @escaping (BridgeMessage) -> Bool) { self.version = version; self.send = send }

    nonisolated(unsafe) static let tools: [[String: Any]] = [   // immutable literal
        ["name": "notify", "description": "Show a short notification in the Dylan notch.",
         "inputSchema": ["type": "object", "properties": ["title": ["type": "string"], "body": ["type": "string"]], "required": ["title"]]],
        ["name": "activity", "description": "Start, update or finish a Live Activity in the notch (e.g. a long task's progress).",
         "inputSchema": ["type": "object", "properties": [
            "id": ["type": "string", "description": "Stable id for this activity"],
            "state": ["type": "string", "enum": ["start", "update", "success", "failure"]],
            "title": ["type": "string"], "subtitle": ["type": "string"], "detail": ["type": "string"],
            "progress": ["type": "number", "minimum": 0, "maximum": 1]], "required": ["id", "state"]]],
        ["name": "shelf_add", "description": "Put files on the Dylan shelf so the user can drag them elsewhere.",
         "inputSchema": ["type": "object", "properties": ["paths": ["type": "array", "items": ["type": "string"]]], "required": ["paths"]]],
    ]

    /// Handles one line; returns the response line, or nil for notifications.
    public func handle(_ line: Data) -> Data? {
        guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let method = o["method"] as? String else { return nil }
        let id = o["id"]
        guard let id else { return nil }   // notifications (e.g. notifications/initialized) get no reply
        let params = o["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            return result(id, ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                               "capabilities": ["tools": [String: Any]()],
                               "serverInfo": ["name": "dylan", "version": version]])
        case "ping":
            return result(id, [:])
        case "tools/list":
            return result(id, ["tools": Self.tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            switch call(name, args) {
            case .success(let text): return result(id, ["content": [["type": "text", "text": text]], "isError": false])
            case .failure(let text): return result(id, ["content": [["type": "text", "text": text]], "isError": true])
            }
        default:
            return encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
    }

    enum CallResult { case success(String), failure(String) }

    func call(_ name: String, _ a: [String: Any]) -> CallResult {
        func str(_ k: String) -> String? { (a[k] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(500)) } }
        let message: BridgeMessage
        switch name {
        case "notify":
            guard let title = str("title") else { return .failure("title is required") }
            message = .notify(title: title, body: str("body"))
        case "activity":
            guard let id = str("id"), let state = str("state") else { return .failure("id and state are required") }
            let p = (a["progress"] as? NSNumber).map { min(1, max(0, $0.doubleValue)) }
            switch state {
            case "start": message = .activityStart(id: "mcp-\(id)", title: str("title") ?? id, subtitle: str("subtitle"), progress: p, url: nil)
            case "update": message = .activityUpdate(id: "mcp-\(id)", title: str("title"), subtitle: str("subtitle"), progress: p)
            case "success", "failure": message = .activityEnd(id: "mcp-\(id)", success: state == "success", detail: str("detail"))
            default: return .failure("state must be start, update, success or failure")
            }
        case "shelf_add":
            guard let paths = (a["paths"] as? [String])?.prefix(50), !paths.isEmpty else { return .failure("paths is required") }
            message = .shelfAdd(paths: Array(paths))
        default:
            return .failure("unknown tool \(name)")
        }
        return send(message) ? .success("ok") : .failure("Dylan is not running")
    }

    private func result(_ id: Any, _ r: [String: Any]) -> Data? { encode(["jsonrpc": "2.0", "id": id, "result": r]) }

    private func encode(_ o: [String: Any]) -> Data? {
        guard var d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        d.append(0x0A)
        return d
    }
}

/// `notify` in ~/.codex/config.toml (FR-32). Codex runs the program with one JSON argument per event.
public enum CodexConfig {
    public static func notifyLine(cliPath: String) -> String {
        let esc = cliPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "notify = [\"\(esc)\", \"hook\", \"codex\"]"
    }

    public static func isInstalled(_ toml: String) -> Bool {
        topLevelNotify(toml).map { toml[$0].contains("hook\", \"codex\"") } ?? false
    }

    /// Sets the top-level `notify` (before the first [table]); replaces an existing one.
    public static func install(_ toml: String, cliPath: String) -> String {
        let line = notifyLine(cliPath: cliPath)
        if let r = topLevelNotify(toml) {
            let keepsNewline = toml[r].hasSuffix("\n")
            return toml.replacingCharacters(in: r, with: line + (keepsNewline ? "\n" : ""))
        }
        return line + "\n" + toml
    }

    /// Removes Dylan's notify line only.
    public static func uninstall(_ toml: String) -> String {
        guard let r = topLevelNotify(toml), toml[r].contains("hook\", \"codex\"") else { return toml }
        var out = toml
        out.removeSubrange(r)
        if out.hasPrefix("\n") { out.removeFirst() }
        return out.replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }

    /// Range of a single-line `notify = …` before any table header.
    static func topLevelNotify(_ toml: String) -> Range<String.Index>? {
        var idx = toml.startIndex
        while idx < toml.endIndex {
            let end = toml[idx...].firstIndex(of: "\n") ?? toml.endIndex
            let line = toml[idx..<end].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { return nil }
            if line.range(of: #"^notify\s*="#, options: .regularExpression) != nil {
                return idx..<(end < toml.endIndex ? toml.index(after: end) : end)
            }
            idx = end < toml.endIndex ? toml.index(after: end) : end
        }
        return nil
    }

    /// The finished-turn message from Codex's notify JSON, if any.
    public static func lastMessage(_ json: JSONValue) -> String? {
        guard json["type"]?.string == "agent-turn-complete" else { return nil }
        return json["last-assistant-message"]?.string
    }
}
