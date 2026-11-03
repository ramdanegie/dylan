import AppKit
import DylanCore
import Security

/// Small Keychain wrapper (generic passwords, this app only).
enum Keychain {
    static let service = "io.github.ramdanegie.dylan"

    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ value: String?, _ account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Discord voice, DMs and mentions over local RPC (FR-65, FR-66), plus a keybind fallback (FR-67).
@Observable
final class DiscordProvider {
    static let shared = DiscordProvider()

    var state = DiscordState()
    var connected = false
    var status: String?

    @ObservationIgnored private var fd: Int32 = -1
    @ObservationIgnored private var retry: Timer?
    @ObservationIgnored private let lock = NSLock()

    var clientID: String { AppModel.shared.discordClientID.trimmingCharacters(in: .whitespaces) }

    func start() {
        guard !clientID.isEmpty, fd < 0 else { return }
        connect()
        if retry == nil {
            let t = Timer(timeInterval: 10, repeats: true) { _ in
                MainActor.assumeIsolated { if DiscordProvider.shared.fd < 0 { DiscordProvider.shared.connect() } }
            }
            RunLoop.main.add(t, forMode: .common)
            retry = t
        }
    }

    func stop() {
        retry?.invalidate(); retry = nil
        disconnect()
    }

    func disconnect() {
        if fd >= 0 { close(fd) }
        fd = -1
        connected = false
        state = DiscordState()
        refreshActivity()
    }

    /// Forget the token (and secret) and disconnect.
    func signOut() {
        Keychain.set(nil, "discord.token")
        Keychain.set(nil, "discord.secret")
        disconnect()
    }

    private func connect() {
        guard !clientID.isEmpty else { return }
        for path in DiscordRPC.socketPaths(tmpdir: NSTemporaryDirectory()) {
            guard let s = try? UnixSocket.connect(path: path, timeout: 1) else { continue }
            fd = s
            connected = true
            status = nil
            send(DiscordFrame.handshake(clientID: clientID))
            let socket = s
            Thread.detachNewThread { DiscordProvider.readLoop(socket) }
            return
        }
        status = L("discord.notRunning")
    }

    nonisolated private static func readLoop(_ fd: Int32) {
        var decoder = DiscordFrame.Decoder()
        var buf = [UInt8](repeating: 0, count: 16384)
        UnixSocket.setTimeouts(fd, 0)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 {
                if n < 0 && errno == EINTR { continue }
                break
            }
            guard let frames = try? decoder.append(Data(buf[0..<n])) else { break }
            for f in frames {
                switch f.opcode {
                case .frame:
                    let json = f.json
                    DispatchQueue.main.async { MainActor.assumeIsolated { DiscordProvider.shared.received(json) } }
                case .ping:
                    let pong = DiscordFrame(opcode: .pong, json: f.json).encoded
                    _ = pong.withUnsafeBytes { write(fd, $0.baseAddress, pong.count) }
                case .close:
                    DispatchQueue.main.async { MainActor.assumeIsolated { DiscordProvider.shared.closed(fd) } }
                    return
                default: break
                }
            }
        }
        DispatchQueue.main.async { MainActor.assumeIsolated { DiscordProvider.shared.closed(fd) } }
    }

    private func closed(_ socket: Int32) {
        guard socket == fd else { return }
        disconnect()
    }

    private func send(_ frame: DiscordFrame) {
        guard fd >= 0 else { return }
        try? UnixSocket.write(fd, frame.encoded)
    }

    private func command(_ json: Data) { send(DiscordFrame(opcode: .frame, json: json)) }

    private func received(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let wasAuthenticated = state.authenticated
        let isAuthError = (obj["cmd"] as? String) == "AUTHENTICATE" && (obj["evt"] as? String) == "ERROR"
        switch state.apply(obj) {
        case .needsAuthorize:
            if let token = Keychain.get("discord.token") { command(DiscordRPC.authenticate(token: token)) }
            else { command(DiscordRPC.authorize(clientID: clientID)); status = L("discord.approveInDiscord") }
        case .exchangeCode(let code):
            exchange(code)
        case .subscribeChannel(let id, let previous):
            if let previous, !previous.isEmpty { for e in DiscordRPC.channelEvents { command(DiscordRPC.unsubscribe(e, channelID: previous)) } }
            if !id.isEmpty { for e in DiscordRPC.channelEvents { command(DiscordRPC.subscribe(e, channelID: id)) } }
        case .message(let m):
            postMessage(m)
        case .none:
            break
        }
        if isAuthError {
            // Expired or revoked token: ask Discord again.
            Keychain.set(nil, "discord.token")
            command(DiscordRPC.authorize(clientID: clientID))
        }
        if state.authenticated && !wasAuthenticated {
            status = nil
            for e in ["VOICE_CHANNEL_SELECT", "VOICE_SETTINGS_UPDATE", "NOTIFICATION_CREATE"] { command(DiscordRPC.subscribe(e)) }
            command(DiscordRPC.command("GET_SELECTED_VOICE_CHANNEL"))
        }
        refreshActivity()
    }

    /// Token exchange is the only network call (discord.com); the token goes to the Keychain.
    private func exchange(_ code: String) {
        var req = URLRequest(url: URL(string: "https://discord.com/api/oauth2/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(DiscordRPC.tokenRequestBody(clientID: clientID, clientSecret: Keychain.get("discord.secret"), code: code).utf8)
        URLSession.shared.dataTask(with: req) { @Sendable data, _, _ in
            let token = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["access_token"] as? String
            Task { @MainActor in
                let p = DiscordProvider.shared
                guard let token else { p.status = L("discord.tokenFailed"); return }
                Keychain.set(token, "discord.token")
                p.command(DiscordRPC.authenticate(token: token))
            }
        }.resume()
    }

    // MARK: Actions

    func toggleMute() { command(DiscordRPC.setMute(!state.selfMute)) }
    func toggleDeaf() { command(DiscordRPC.setDeaf(!state.selfDeaf)) }
    func leave() { command(DiscordRPC.leaveVoice()) }

    // MARK: Notch

    private func postMessage(_ m: DiscordState.Message) {
        guard AppModel.shared.discordMessages else { return }
        let now = Date()
        AppModel.shared.center.post(Activity(
            id: "discord-msg-\(now.timeIntervalSince1970)", kind: .notify, priority: .p1, state: .info, symbol: "bubble.left.fill",
            label: TextRules.truncateTail(m.author, max: 10), value: "",
            detail: L("discord.messageIn", m.author, m.channel) + " · " + TextRules.truncateTail(TextRules.singleLine(m.body), max: 80),
            genericDetail: L("discord.messageGeneric"), url: DiscordState.deepLink(m)?.absoluteString, startedAt: now), now: now)
        AppModel.shared.scheduleTick()
    }

    func refreshActivity() {
        let m = AppModel.shared
        let now = Date()
        guard m.features.isEnabled(.discord), state.inVoice else {
            if m.center.activities["discord-voice"] != nil { m.center.remove("discord-voice", now: now) }
            return
        }
        let a = Activity(id: "discord-voice", kind: .discord, priority: .p2, state: .running,
                         symbol: state.selfDeaf ? "headphones" : (state.selfMute ? "mic.slash.fill" : "mic.fill"),
                         label: state.selfDeaf ? L("discord.deafened") : (state.selfMute ? L("discord.muted") : ""),
                         value: "\(state.members.count)",
                         detail: L("discord.voiceDetail", state.channelName ?? "voice", state.members.count),
                         genericDetail: L("discord.voiceGeneric"), startedAt: m.center.activities["discord-voice"]?.startedAt ?? now,
                         updatedAt: m.center.activities["discord-voice"]?.updatedAt ?? now)
        if m.center.activities["discord-voice"] != a { m.center.upsert(a) }
    }

    // MARK: Simple mode (FR-67): keybinds, no RPC

    /// Sends the user's Discord keybind (configured to match Discord → Settings → Keybinds). Needs Accessibility.
    func sendKeybind(_ combo: String) {
        guard AXIsProcessTrusted(), let (key, flags) = Self.parseCombo(combo) else { return }
        let src = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    /// "⌃⇧M" → (keycode, flags). Letters A–Z only.
    nonisolated static func parseCombo(_ s: String) -> (CGKeyCode, CGEventFlags)? {
        var flags: CGEventFlags = []
        if s.contains("⌃") { flags.insert(.maskControl) }
        if s.contains("⇧") { flags.insert(.maskShift) }
        if s.contains("⌥") { flags.insert(.maskAlternate) }
        if s.contains("⌘") { flags.insert(.maskCommand) }
        guard let letter = s.uppercased().last, let code = keyCodes[letter], !flags.isEmpty else { return nil }
        return (code, flags)
    }

    nonisolated static let keyCodes: [Character: CGKeyCode] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14,
        "R": 15, "Y": 16, "T": 17, "O": 31, "U": 32, "I": 34, "P": 35, "L": 37, "J": 38, "K": 40, "N": 45, "M": 46,
    ]
}
