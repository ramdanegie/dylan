import Foundation

/// Installs / removes Dylan's hooks in `~/.claude/settings.json` without touching anything else. FR-8, PRD §F3.
/// Only the JSON transformation lives here; backup, diff approval and the atomic write are done by the caller.
public enum HookInstaller {
    public struct Event: Sendable {
        public let name: String
        public let matcher: String?
        public let timeout: Int
    }

    /// PRD §2.6. PermissionRequest waits for the notch, so its timeout must exceed Dylan's 30 s limit.
    public static let events: [Event] = [
        Event(name: "SessionStart", matcher: nil, timeout: 5),
        Event(name: "UserPromptSubmit", matcher: nil, timeout: 5),
        Event(name: "PreToolUse", matcher: "*", timeout: 5),
        Event(name: "PostToolUse", matcher: "*", timeout: 5),
        Event(name: "Notification", matcher: nil, timeout: 5),
        Event(name: "PermissionRequest", matcher: "*", timeout: 60),
        Event(name: "Stop", matcher: nil, timeout: 5),
        Event(name: "SessionEnd", matcher: nil, timeout: 5),
    ]

    /// A hook belongs to Dylan when its command runs `dylan hook <agent>` (path optionally quoted;
    /// `dylan-cli` is the unbundled dev build).
    public static func isDylanHook(_ command: String) -> Bool {
        command.range(of: #"(^|/)dylan(-cli)?'?\s+hook\s+(claude|codex)\b"#, options: .regularExpression) != nil
    }

    public enum Status: Equatable, Sendable {
        case notInstalled
        case installed
        /// Installed, but pointing at another path (app moved) or missing some events.
        case needsUpdate
    }

    public enum MergeError: Error, Equatable {
        case notAnObject, hooksNotAnObject, eventNotAnArray(String)
    }

    public struct Result: Equatable, Sendable {
        public var json: Data
        public var added: Int
        public var updated: Int
        public var removed: Int
    }

    /// `'…/Dylan.app/Contents/Helpers/dylan' hook claude`. Always single-quoted: Claude Code runs hooks
    /// through a shell, and characters like `(`, `&` or spaces in the path would break it.
    public static func command(cliPath: String) -> String {
        "'" + cliPath.replacingOccurrences(of: "'", with: "'\\''") + "' hook claude"
    }

    public static func status(_ data: Data?, command: String) throws -> Status {
        guard let data, !data.isEmpty else { return .notInstalled }
        let root = try object(data)
        guard let hooks = root["hooks"] as? [String: Any] else { return .notInstalled }
        var found = 0, exact = 0
        for e in events {
            for h in dylanHooks(in: hooks[e.name]) {
                found += 1
                if h == command { exact += 1 }
            }
        }
        if found == 0 { return .notInstalled }
        return exact == events.count && found == events.count ? .installed : .needsUpdate
    }

    public static func install(into data: Data?, command: String) throws -> Result {
        var root = (data?.isEmpty ?? true) ? [:] : try object(data!)
        var hooks: [String: Any]
        if let h = root["hooks"] {
            guard let h = h as? [String: Any] else { throw MergeError.hooksNotAnObject }
            hooks = h
        } else { hooks = [:] }

        var added = 0, updated = 0
        for e in events {
            var groups: [[String: Any]]
            if let g = hooks[e.name] {
                guard let g = g as? [[String: Any]] else { throw MergeError.eventNotAnArray(e.name) }
                groups = g
            } else { groups = [] }

            var present = false
            for gi in groups.indices {
                guard var list = groups[gi]["hooks"] as? [[String: Any]] else { continue }
                for hi in list.indices where (list[hi]["command"] as? String).map(isDylanHook) == true {
                    if !present {
                        present = true
                        if list[hi]["command"] as? String != command || list[hi]["timeout"] as? Int != e.timeout {
                            list[hi]["command"] = command
                            list[hi]["timeout"] = e.timeout
                            updated += 1
                        }
                    }
                }
                groups[gi]["hooks"] = list
            }
            if !present {
                var group: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": e.timeout]]]
                if let m = e.matcher { group["matcher"] = m }
                groups.append(group)
                added += 1
            }
            hooks[e.name] = groups
        }
        root["hooks"] = hooks
        return Result(json: try serialize(root), added: added, updated: updated, removed: 0)
    }

    /// Removes every hook whose command contains `dylan hook`, then empty groups/events.
    public static func uninstall(from data: Data) throws -> Result {
        var root = try object(data)
        guard let anyHooks = root["hooks"] else { return Result(json: try serialize(root), added: 0, updated: 0, removed: 0) }
        guard var hooks = anyHooks as? [String: Any] else { throw MergeError.hooksNotAnObject }
        var removed = 0
        for (name, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            for gi in groups.indices {
                guard let list = groups[gi]["hooks"] as? [[String: Any]] else { continue }
                let kept = list.filter { ($0["command"] as? String).map(isDylanHook) != true }
                guard kept.count != list.count else { continue }
                removed += list.count - kept.count
                groups[gi]["hooks"] = kept
                // Only groups that became empty because of us are dropped; the user's own empty groups stay.
                if kept.isEmpty { groups[gi]["__dylanEmptied"] = true }
            }
            groups.removeAll { $0["__dylanEmptied"] as? Bool == true }
            hooks[name] = groups.isEmpty ? nil : groups
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        return Result(json: try serialize(root), added: 0, updated: 0, removed: removed)
    }

    static func dylanHooks(in value: Any?) -> [String] {
        guard let groups = value as? [[String: Any]] else { return [] }
        return groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
            .filter(isDylanHook)
    }

    static func object(_ data: Data) throws -> [String: Any] {
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MergeError.notAnObject }
        return o
    }

    public static func serialize(_ o: [String: Any]) throws -> Data {
        var d = try JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        d.append(0x0A)
        return d
    }

    /// Pretty-prints existing settings the same way, so the diff only shows real changes.
    public static func normalized(_ data: Data?) throws -> Data {
        guard let data, !data.isEmpty else { return Data() }
        return try serialize(try object(data))
    }
}

/// Minimal line diff (LCS) for the "Lihat diff" view. Settings files are small.
public enum LineDiff {
    public enum Line: Equatable, Sendable {
        case same(String), added(String), removed(String)
    }

    public static func diff(old: String, new: String) -> [Line] {
        let a = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let b = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out: [Line] = []
        var i = 0, j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { out.append(.same(a[i])); i += 1; j += 1 }
            else if lcs[i + 1][j] >= lcs[i][j + 1] { out.append(.removed(a[i])); i += 1 }
            else { out.append(.added(b[j])); j += 1 }
        }
        while i < a.count { out.append(.removed(a[i])); i += 1 }
        while j < b.count { out.append(.added(b[j])); j += 1 }
        return out
    }
}
