import Foundation

/// Discord local RPC: commands and the voice/notification state they produce (FR-65–67, PRD §F17).
/// Transport (unix socket + DiscordFrame) lives in the app; this is the pure protocol part.
public enum DiscordRPC {
    public static let scopes = ["rpc", "rpc.voice.read", "rpc.voice.write", "rpc.notifications.read"]

    /// `$TMPDIR/discord-ipc-0` … `-9` (Stable, PTB and Canary share the numbering).
    public static func socketPaths(tmpdir: String) -> [String] {
        (0...9).map { (tmpdir as NSString).appendingPathComponent("discord-ipc-\($0)") }
    }

    public static func command(_ cmd: String, args: [String: Any] = [:], evt: String? = nil, nonce: String = UUID().uuidString) -> Data {
        var o: [String: Any] = ["cmd": cmd, "args": args, "nonce": nonce]
        if let evt { o["evt"] = evt }
        return (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])) ?? Data()
    }

    public static func authorize(clientID: String) -> Data { command("AUTHORIZE", args: ["client_id": clientID, "scopes": scopes]) }
    public static func authenticate(token: String) -> Data { command("AUTHENTICATE", args: ["access_token": token]) }
    public static func subscribe(_ evt: String, channelID: String? = nil) -> Data {
        command("SUBSCRIBE", args: channelID.map { ["channel_id": $0] } ?? [:], evt: evt)
    }
    public static func unsubscribe(_ evt: String, channelID: String) -> Data { command("UNSUBSCRIBE", args: ["channel_id": channelID], evt: evt) }
    public static func setMute(_ on: Bool) -> Data { command("SET_VOICE_SETTINGS", args: ["mute": on]) }
    public static func setDeaf(_ on: Bool) -> Data { command("SET_VOICE_SETTINGS", args: ["deaf": on]) }
    public static func leaveVoice() -> Data { command("SELECT_VOICE_CHANNEL", args: ["channel_id": NSNull()]) }
    public static let channelEvents = ["VOICE_STATE_CREATE", "VOICE_STATE_UPDATE", "VOICE_STATE_DELETE", "SPEAKING_START", "SPEAKING_STOP"]

    /// Form body for exchanging the AUTHORIZE code at discord.com/api/oauth2/token.
    public static func tokenRequestBody(clientID: String, clientSecret: String?, code: String) -> String {
        var items = [("client_id", clientID), ("grant_type", "authorization_code"), ("code", code)]
        if let s = clientSecret, !s.isEmpty { items.append(("client_secret", s)) }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return items.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&")
    }
}

/// Voice channel + DM state built from RPC messages.
public struct DiscordState: Equatable, Sendable {
    public struct Member: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var avatarURL: String?
        public var muted: Bool
        public var deafened: Bool
        public var speaking: Bool
    }

    public struct Message: Equatable, Sendable {
        public var author: String
        public var channel: String
        public var body: String
        public var channelID: String?
        public var guildID: String?
    }

    public var ready = false
    public var authenticated = false
    public var userID: String?
    public var channelID: String?
    public var channelName: String?
    public var guildName: String?
    public var members: [Member] = []
    public var selfMute = false
    public var selfDeaf = false
    /// Most recent speaker first, for the avatar stack (design M9).
    public var speakingOrder: [String] = []
    public var lastMessage: Message?
    public var lastError: String?

    public init() {}

    public var inVoice: Bool { channelID != nil }
    public var speakers: [Member] { speakingOrder.compactMap { id in members.first { $0.id == id && $0.speaking } } }

    public enum Effect: Equatable, Sendable {
        case none
        case needsAuthorize
        case exchangeCode(String)
        case subscribeChannel(String, previous: String?)
        case message(Message)
    }

    /// Applies one decoded JSON frame and says what the transport should do next.
    public mutating func apply(_ json: [String: Any]) -> Effect {
        let cmd = json["cmd"] as? String
        let evt = json["evt"] as? String
        let data = json["data"] as? [String: Any] ?? [:]
        if evt == "ERROR" { lastError = data["message"] as? String; return .none }
        switch (cmd, evt) {
        case ("DISPATCH", "READY"?):
            ready = true
            userID = (data["user"] as? [String: Any])?["id"] as? String
            return .needsAuthorize
        case ("AUTHORIZE", _):
            return (data["code"] as? String).map(Effect.exchangeCode) ?? .none
        case ("AUTHENTICATE", _):
            authenticated = true
            if let u = (data["user"] as? [String: Any])?["id"] as? String { userID = u }
            return .none
        case ("GET_SELECTED_VOICE_CHANNEL", _), ("DISPATCH", "VOICE_CHANNEL_SELECT"?):
            let previous = channelID
            let id = (data["id"] as? String) ?? (data["channel_id"] as? String)
            if id == nil || (data.isEmpty) {
                channelID = nil; channelName = nil; guildName = nil; members = []; speakingOrder = []
                return previous.map { .subscribeChannel("", previous: $0) } ?? .none
            }
            channelID = id
            if let n = data["name"] as? String { channelName = n }
            if let states = data["voice_states"] as? [[String: Any]] { members = states.compactMap(Self.member) }
            updateSelf()
            return id == previous ? .none : .subscribeChannel(id!, previous: previous)
        case ("DISPATCH", "VOICE_STATE_CREATE"?), ("DISPATCH", "VOICE_STATE_UPDATE"?):
            guard let m = Self.member(data) else { return .none }
            if let i = members.firstIndex(where: { $0.id == m.id }) {
                var updated = m
                updated.speaking = members[i].speaking
                members[i] = updated
            } else { members.append(m) }
            updateSelf()
            return .none
        case ("DISPATCH", "VOICE_STATE_DELETE"?):
            if let id = ((data["user"] as? [String: Any])?["id"] as? String) {
                members.removeAll { $0.id == id }
                speakingOrder.removeAll { $0 == id }
            }
            return .none
        case ("DISPATCH", "SPEAKING_START"?), ("DISPATCH", "SPEAKING_STOP"?):
            guard let id = data["user_id"] as? String, let i = members.firstIndex(where: { $0.id == id }) else { return .none }
            let on = evt == "SPEAKING_START"
            members[i].speaking = on
            speakingOrder.removeAll { $0 == id }
            if on { speakingOrder.insert(id, at: 0) }
            return .none
        case ("DISPATCH", "VOICE_SETTINGS_UPDATE"?):
            if let m = data["mute"] as? Bool { selfMute = m }
            if let d = data["deaf"] as? Bool { selfDeaf = d }
            return .none
        case ("DISPATCH", "NOTIFICATION_CREATE"?):
            let msg = data["message"] as? [String: Any] ?? [:]
            let author = (msg["author"] as? [String: Any])?["username"] as? String ?? (data["title"] as? String ?? "Discord")
            let m = Message(author: author, channel: data["title"] as? String ?? "", body: (data["body"] as? String) ?? (msg["content"] as? String ?? ""),
                            channelID: data["channel_id"] as? String, guildID: nil)
            lastMessage = m
            return .message(m)
        default:
            return .none
        }
    }

    private mutating func updateSelf() {
        guard let me = members.first(where: { $0.id == userID }) else { return }
        selfMute = me.muted
        selfDeaf = me.deafened
    }

    static func member(_ s: [String: Any]) -> Member? {
        guard let user = s["user"] as? [String: Any], let id = user["id"] as? String else { return nil }
        let vs = s["voice_state"] as? [String: Any] ?? [:]
        let name = (s["nick"] as? String) ?? (user["global_name"] as? String) ?? (user["username"] as? String) ?? id
        let avatar = (user["avatar"] as? String).map { "https://cdn.discordapp.com/avatars/\(id)/\($0).png?size=64" }
        return Member(id: id, name: name, avatarURL: avatar,
                      muted: (vs["mute"] as? Bool ?? false) || (vs["self_mute"] as? Bool ?? false),
                      deafened: (vs["deaf"] as? Bool ?? false) || (vs["self_deaf"] as? Bool ?? false), speaking: false)
    }

    /// `discord://-/channels/<guild>/<channel>` (DMs use `@me`).
    public static func deepLink(_ m: Message) -> URL? {
        guard let ch = m.channelID else { return URL(string: "discord://") }
        return URL(string: "discord://-/channels/\(m.guildID ?? "@me")/\(ch)")
    }
}
