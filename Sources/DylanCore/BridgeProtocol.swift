import Foundation

/// Socket protocol between the `dylan` CLI and the app. PRD §2.6.
/// One JSON object per line, always with `"v": 1`.
public enum Bridge {
    public static let version = 1
    /// Messages above this size are rejected (PRD §2.8).
    public static let maxMessageBytes = 64 * 1024

    public static var socketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dylan/dylan.sock")
    }
}

public enum BridgeMessage: Equatable, Sendable {
    case activityStart(id: String, title: String, subtitle: String?, progress: Double?, url: String?)
    case activityUpdate(id: String, title: String?, subtitle: String?, progress: Double?)
    case activityEnd(id: String, success: Bool, detail: String?)
    case notify(title: String, body: String?)
    case shellStart(shellPid: Int, cmd: String, cwd: String, app: String?)
    case shellEnd(shellPid: Int, status: Int)
    case hook(source: String, env: [String: String], payload: JSONValue)
    /// The CLI waits on the same connection for a `PermissionReply`.
    case permissionAsk(requestId: String, source: String, env: [String: String], payload: JSONValue)
    case shelfAdd(paths: [String])
    case ping
    /// Debug: the app replies with its current activities as JSON (used by tests and `dylan debug state`).
    case debugState
}

public enum PermissionDecision: String, Codable, Sendable {
    case allow, deny, passthrough
}

public struct PermissionReply: Codable, Equatable, Sendable {
    public var decision: PermissionDecision
    public var message: String?
    public init(decision: PermissionDecision, message: String? = nil) {
        self.decision = decision; self.message = message
    }
}

public struct PingReply: Codable, Equatable, Sendable {
    public var ok: Bool
    public var version: String
    public var profile: String
    public init(ok: Bool, version: String, profile: String) {
        self.ok = ok; self.version = version; self.profile = profile
    }
}

public enum BridgeError: Error, Equatable {
    case tooLarge, unsupportedVersion(Int), unknownType(String), invalid(String)
}

extension BridgeMessage: Codable {
    private enum K: String, CodingKey {
        case v, type, id, title, subtitle, progress, url, result, detail, body
        case shellPid, cmd, cwd, app, status, source, env, payload, requestId, paths
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 0
        guard v == Bridge.version else { throw BridgeError.unsupportedVersion(v) }
        let type = try c.decode(String.self, forKey: .type)
        func s(_ k: K) throws -> String { try c.decode(String.self, forKey: k) }
        func os(_ k: K) throws -> String? { try c.decodeIfPresent(String.self, forKey: k) }
        switch type {
        case "activity.start":
            self = .activityStart(id: try s(.id), title: try s(.title), subtitle: try os(.subtitle),
                                  progress: try c.decodeIfPresent(Double.self, forKey: .progress), url: try os(.url))
        case "activity.update":
            self = .activityUpdate(id: try s(.id), title: try os(.title), subtitle: try os(.subtitle),
                                   progress: try c.decodeIfPresent(Double.self, forKey: .progress))
        case "activity.end":
            let r = try s(.result)
            guard r == "success" || r == "failure" else { throw BridgeError.invalid("result") }
            self = .activityEnd(id: try s(.id), success: r == "success", detail: try os(.detail))
        case "notify":
            self = .notify(title: try s(.title), body: try os(.body))
        case "shell.start":
            self = .shellStart(shellPid: try c.decode(Int.self, forKey: .shellPid), cmd: try s(.cmd),
                               cwd: try s(.cwd), app: try os(.app))
        case "shell.end":
            self = .shellEnd(shellPid: try c.decode(Int.self, forKey: .shellPid),
                             status: try c.decode(Int.self, forKey: .status))
        case "hook":
            self = .hook(source: try s(.source), env: try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:],
                         payload: try c.decodeIfPresent(JSONValue.self, forKey: .payload) ?? .null)
        case "permission.ask":
            self = .permissionAsk(requestId: try s(.requestId), source: try s(.source),
                                  env: try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:],
                                  payload: try c.decodeIfPresent(JSONValue.self, forKey: .payload) ?? .null)
        case "shelf.add":
            self = .shelfAdd(paths: try c.decode([String].self, forKey: .paths))
        case "ping":
            self = .ping
        case "debug.state":
            self = .debugState
        default:
            throw BridgeError.unknownType(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(Bridge.version, forKey: .v)
        switch self {
        case let .activityStart(id, title, subtitle, progress, url):
            try c.encode("activity.start", forKey: .type)
            try c.encode(id, forKey: .id); try c.encode(title, forKey: .title)
            try c.encodeIfPresent(subtitle, forKey: .subtitle)
            try c.encodeIfPresent(progress, forKey: .progress); try c.encodeIfPresent(url, forKey: .url)
        case let .activityUpdate(id, title, subtitle, progress):
            try c.encode("activity.update", forKey: .type)
            try c.encode(id, forKey: .id); try c.encodeIfPresent(title, forKey: .title)
            try c.encodeIfPresent(subtitle, forKey: .subtitle); try c.encodeIfPresent(progress, forKey: .progress)
        case let .activityEnd(id, success, detail):
            try c.encode("activity.end", forKey: .type)
            try c.encode(id, forKey: .id); try c.encode(success ? "success" : "failure", forKey: .result)
            try c.encodeIfPresent(detail, forKey: .detail)
        case let .notify(title, body):
            try c.encode("notify", forKey: .type)
            try c.encode(title, forKey: .title); try c.encodeIfPresent(body, forKey: .body)
        case let .shellStart(pid, cmd, cwd, app):
            try c.encode("shell.start", forKey: .type)
            try c.encode(pid, forKey: .shellPid); try c.encode(cmd, forKey: .cmd)
            try c.encode(cwd, forKey: .cwd); try c.encodeIfPresent(app, forKey: .app)
        case let .shellEnd(pid, status):
            try c.encode("shell.end", forKey: .type)
            try c.encode(pid, forKey: .shellPid); try c.encode(status, forKey: .status)
        case let .hook(source, env, payload):
            try c.encode("hook", forKey: .type)
            try c.encode(source, forKey: .source); try c.encode(env, forKey: .env); try c.encode(payload, forKey: .payload)
        case let .permissionAsk(requestId, source, env, payload):
            try c.encode("permission.ask", forKey: .type)
            try c.encode(requestId, forKey: .requestId); try c.encode(source, forKey: .source)
            try c.encode(env, forKey: .env); try c.encode(payload, forKey: .payload)
        case let .shelfAdd(paths):
            try c.encode("shelf.add", forKey: .type); try c.encode(paths, forKey: .paths)
        case .ping:
            try c.encode("ping", forKey: .type)
        case .debugState:
            try c.encode("debug.state", forKey: .type)
        }
    }

    /// Decodes one line. Rejects oversized input before parsing.
    public static func decode(line: Data) throws -> BridgeMessage {
        guard line.count <= Bridge.maxMessageBytes else { throw BridgeError.tooLarge }
        return try JSONDecoder().decode(BridgeMessage.self, from: line)
    }

    /// Encodes as a single line terminated by `\n`.
    public func encodedLine() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var d = try e.encode(self)
        d.append(0x0A)
        return d
    }
}

/// Splits a byte stream into newline-terminated lines, enforcing the size limit.
public struct LineBuffer: Sendable {
    private var buffer = Data()
    public init() {}

    /// Appends bytes and returns complete lines. Throws once a line grows past the limit.
    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            if !line.isEmpty { lines.append(Data(line)) }
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        if buffer.count > Bridge.maxMessageBytes { buffer.removeAll(); throw BridgeError.tooLarge }
        return lines
    }
}
