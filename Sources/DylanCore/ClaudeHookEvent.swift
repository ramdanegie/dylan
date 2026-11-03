import Foundation

/// A Claude Code hook payload reduced to what Dylan needs. PRD §F3.
/// Unknown fields and events are ignored so new Claude Code versions do not break parsing.
public struct ClaudeHookEvent: Equatable, Sendable {
    public enum Name: String, Sendable {
        case sessionStart = "SessionStart"
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case postToolUseFailure = "PostToolUseFailure"
        case notification = "Notification"
        case permissionRequest = "PermissionRequest"
        case stop = "Stop"
        case stopFailure = "StopFailure"
        case sessionEnd = "SessionEnd"
    }

    public var name: Name
    public var sessionID: String
    public var cwd: String?
    public var toolName: String?
    /// File name (Edit/Write/Read) or truncated command (Bash), ready for display.
    public var toolDetail: String?
    public var changedFile: String?
    public var notificationType: String?
    public var message: String?
    public var lastAssistantMessage: String?

    /// Returns nil for events Dylan does not handle or payloads without a session.
    public init?(payload: JSONValue) {
        guard let raw = payload["hook_event_name"]?.string, let name = Name(rawValue: raw),
              let sid = payload["session_id"]?.string, !sid.isEmpty else { return nil }
        self.name = name
        sessionID = sid
        cwd = payload["cwd"]?.string
        toolName = payload["tool_name"]?.string
        notificationType = payload["notification_type"]?.string
        message = payload["message"]?.string
        lastAssistantMessage = payload["last_assistant_message"]?.string
        let input = payload["tool_input"]
        toolDetail = Self.detail(tool: toolName, input: input)
        if name == .postToolUse, let t = toolName, ["Edit", "Write", "MultiEdit", "NotebookEdit"].contains(t) {
            changedFile = input?["file_path"]?.string ?? input?["notebook_path"]?.string
        }
    }

    static func detail(tool: String?, input: JSONValue?) -> String? {
        guard let tool else { return nil }
        switch tool {
        case "Edit", "Write", "Read", "MultiEdit":
            return input?["file_path"]?.string.map { ($0 as NSString).lastPathComponent }
        case "NotebookEdit":
            return input?["notebook_path"]?.string.map { ($0 as NSString).lastPathComponent }
        case "Bash":
            return input?["command"]?.string.map { TextRules.truncateTail(TextRules.singleLine($0), max: 60) }
        case "Grep", "Glob":
            return input?["pattern"]?.string.map { TextRules.truncateTail($0, max: 60) }
        case "WebFetch":
            return input?["url"]?.string.map { TextRules.truncateTail($0, max: 60) }
        default:
            return nil
        }
    }
}

/// Live state of every Claude Code session seen through hooks.
public struct AgentSessions: Sendable, Equatable {
    public enum Status: Equatable, Sendable {
        case idle
        case working(tool: String?, detail: String?)
        case needsPermission(requestID: String?, tool: String?, detail: String?)
        case waitingInput
        case done(duration: TimeInterval, summary: String?)
        case failed(message: String?)
    }

    public struct Session: Equatable, Sendable, Identifiable {
        public var id: String
        public var cwd: String?
        public var project: String
        /// `__CFBundleIdentifier` of the terminal/editor the session runs in.
        public var appBundleID: String?
        public var termProgram: String?
        public var status: Status = .idle
        public var promptStartedAt: Date?
        public var changedFiles: Set<String> = []
        public var updatedAt: Date
    }

    public private(set) var sessions: [String: Session] = [:]
    public init() {}

    /// Applies one hook event. `projectName` maps a cwd to a display name (git root or folder).
    public mutating func apply(_ e: ClaudeHookEvent, env: [String: String], now: Date,
                               projectName: (String) -> String) {
        if e.name == .sessionEnd { sessions[e.sessionID] = nil; return }
        var s = sessions[e.sessionID] ?? Session(
            id: e.sessionID, cwd: e.cwd, project: e.cwd.map(projectName) ?? "Claude",
            appBundleID: env["__CFBundleIdentifier"], termProgram: env["TERM_PROGRAM"], updatedAt: now)
        if let cwd = e.cwd, cwd != s.cwd { s.cwd = cwd; s.project = projectName(cwd) }
        if s.appBundleID == nil { s.appBundleID = env["__CFBundleIdentifier"] }
        if s.termProgram == nil { s.termProgram = env["TERM_PROGRAM"] }
        s.updatedAt = now

        switch e.name {
        case .sessionStart:
            s.status = .idle
        case .userPromptSubmit:
            s.status = .working(tool: nil, detail: nil)
            s.promptStartedAt = now
            s.changedFiles = []
        case .preToolUse:
            s.status = .working(tool: e.toolName, detail: e.toolDetail)
            if s.promptStartedAt == nil { s.promptStartedAt = now }
        case .postToolUse:
            if let f = e.changedFile { s.changedFiles.insert(f) }
            if case .needsPermission = s.status { s.status = .working(tool: e.toolName, detail: e.toolDetail) }
        case .postToolUseFailure:
            break
        case .notification:
            if e.notificationType == "permission_prompt" {
                if case .needsPermission = s.status {} else {
                    // The message is generic ("Claude needs your permission"); the tool comes from PermissionRequest.
                    s.status = .needsPermission(requestID: nil, tool: nil, detail: nil)
                }
            } else if e.notificationType == "idle_prompt" || e.notificationType == nil {
                if case .done = s.status {} else { s.status = .waitingInput }
            }
        case .permissionRequest:
            s.status = .needsPermission(requestID: nil, tool: e.toolName, detail: e.toolDetail)
        case .stop:
            let d = s.promptStartedAt.map { now.timeIntervalSince($0) } ?? 0
            s.status = .done(duration: d, summary: e.lastAssistantMessage.map(TextRules.firstSentence))
            s.promptStartedAt = nil
        case .stopFailure:
            s.status = .failed(message: e.message)
            s.promptStartedAt = nil
        case .sessionEnd:
            break
        }
        sessions[e.sessionID] = s
    }

    /// Marks a pending notch permission card (from `permission.ask`) on its session.
    public mutating func setPermission(sessionID: String, requestID: String?, tool: String?, detail: String?, now: Date) {
        guard var s = sessions[sessionID] else { return }
        s.status = .needsPermission(requestID: requestID, tool: tool, detail: detail)
        s.updatedAt = now
        sessions[sessionID] = s
    }

    /// The answer was given (or released to the terminal): back to working.
    public mutating func clearPermission(requestID: String, now: Date) {
        for (id, var s) in sessions {
            if case .needsPermission(let r, let tool, let detail) = s.status, r == requestID {
                s.status = .working(tool: tool, detail: detail)
                s.updatedAt = now
                sessions[id] = s
            }
        }
    }

    public func hasStale(now: Date, after: TimeInterval = 2 * 3600) -> Bool {
        sessions.values.contains { now.timeIntervalSince($0.updatedAt) >= after }
    }

    /// Sessions that saw no hook event for `after` (Claude quit without SessionEnd) are dropped.
    @discardableResult
    public mutating func expireStale(now: Date, after: TimeInterval = 2 * 3600) -> [String] {
        let stale = sessions.values.filter { now.timeIntervalSince($0.updatedAt) >= after }.map(\.id)
        for id in stale { sessions[id] = nil }
        return stale
    }

    /// Done/failed sessions are shown once; afterwards they go back to idle.
    public mutating func acknowledgeResult(sessionID: String) {
        guard var s = sessions[sessionID] else { return }
        switch s.status {
        case .done, .failed: s.status = .idle; sessions[sessionID] = s
        default: break
        }
    }

    public var ordered: [Session] {
        sessions.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    public var active: [Session] {
        ordered.filter { if case .idle = $0.status { return false }; return true }
    }

    public var permissionCount: Int {
        sessions.values.filter { if case .needsPermission = $0.status { return true }; return false }.count
    }
}

/// Finds a display name for a working directory: the git root's folder name, else the folder name.
/// `exists` is injected so tests do not touch the disk; `.git` may be a directory or a file (worktrees).
public enum ProjectName {
    public static func resolve(cwd: String, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
        var url = URL(fileURLWithPath: cwd).standardizedFileURL
        while url.path != "/" {
            if exists(url.appendingPathComponent(".git").path) { return url.lastPathComponent }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

/// Parses `git diff --shortstat` output into (+insertions, −deletions).
public enum ShortStat {
    public static func parse(_ s: String) -> (added: Int, removed: Int)? {
        guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        func num(before word: String) -> Int {
            guard let r = s.range(of: #"(\d+) \#(word)"#, options: .regularExpression) else { return 0 }
            return Int(s[r].split(separator: " ")[0]) ?? 0
        }
        return (num(before: "insertion"), num(before: "deletion"))
    }
}

/// Hook payloads can be huge (`Write` carries the whole file). The CLI keeps only what Dylan reads,
/// so messages stay under the 64 KB socket limit and file contents never reach the app.
public enum HookPayload {
    static let topLevel: Set<String> = [
        "hook_event_name", "session_id", "cwd", "tool_name", "tool_input", "notification_type",
        "message", "title", "last_assistant_message", "source", "reason", "permission_mode",
    ]
    static let toolInput: Set<String> = ["file_path", "notebook_path", "command", "pattern", "url", "description"]

    public static func slim(_ payload: JSONValue) -> JSONValue {
        guard case .object(let o) = payload else { return payload }
        var out: [String: JSONValue] = [:]
        for (k, v) in o where topLevel.contains(k) {
            if k == "tool_input", case .object(let input) = v {
                out[k] = .object(input.filter { toolInput.contains($0.key) }.mapValues(clip))
            } else {
                out[k] = clip(v)
            }
        }
        return .object(out)
    }

    /// Codex notify JSON: keep the event type, cwd and the (clipped) last message only.
    public static func slimCodex(_ payload: JSONValue) -> JSONValue {
        guard case .object(let o) = payload else { return .null }
        return .object(o.filter { ["type", "cwd", "turn-id", "last-assistant-message"].contains($0.key) }.mapValues(clip))
    }

    private static func clip(_ v: JSONValue) -> JSONValue {
        if case .string(let s) = v, s.count > 2000 { return .string(String(s.prefix(2000))) }
        if case .object = v { return .null }   // nested objects outside tool_input are never read
        if case .array = v { return .null }
        return v
    }
}
