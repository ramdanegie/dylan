import Foundation
import Security
import SMCKit
@preconcurrency import XPC

// Root launchd daemon (FR-99, design D49), installed by Dylan with SMAppService. It only:
//   set  {fan, rpm} → manual at rpm, clamped to the factory range
//   auto {fan}      → hand one fan (or all, fan < 0) back to macOS
//   ping            → heartbeat
// Every fan it takes is handed back when Dylan disconnects, after 10 s of silence, on SIGTERM, and after a crash
// (the owned list lives in /var/run and launchd restarts the helper).

guard getuid() == 0, SMC() != nil else {
    FileHandle.standardError.write(Data("dylan-fan-helper: needs root and AppleSMC\n".utf8))
    exit(1)
}

/// All state lives on the main queue; every XPC and dispatch handler below targets .main.
enum Helper {
    static let smc = SMC()!
    static let ownedFile = "/var/run/\(FanHelperAPI.label).owned"
    static var owned: Set<Int> = [] {
        didSet { try? owned.map(String.init).joined(separator: ",").write(toFile: ownedFile, atomically: true, encoding: .utf8) }
    }
    static var controller: xpc_connection_t?
    static var lastMessage = Date()

    static func restore(_ fans: Set<Int>? = nil) {
        let fans = fans ?? owned
        for i in fans { smc.setAuto(i) }
        owned.subtract(fans)
    }

    /// A previous run that crashed while a fan was manual.
    static func recover() {
        guard let s = try? String(contentsOfFile: ownedFile, encoding: .utf8) else { return }
        for i in s.split(separator: ",").compactMap({ Int($0) }) { smc.setAuto(i) }
        try? FileManager.default.removeItem(atPath: ownedFile)
    }

    /// Dylan signed by the same team as this helper. Ad-hoc builds have no team, so nothing can connect.
    static let requirement: String? = {
        var code: SecCode?, staticCode: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty
        else { return nil }
        return "anchor apple generic and identifier \"io.github.ramdanegie.dylan\" and certificate leaf[subject.OU] = \"\(team)\""
    }()

    static func handle(_ m: xpc_object_t, from peer: xpc_connection_t) -> Bool {
        guard let op = xpc_dictionary_get_string(m, "op").map({ String(cString: $0) }) else { return false }
        let fan = Int(xpc_dictionary_get_int64(m, "fan"))
        switch op {
        case "set":
            let rpm = xpc_dictionary_get_double(m, "rpm")
            guard fan >= 0, fan < smc.fanCount, rpm.isFinite, smc.setManual(fan, rpm: rpm) else { return false }
            owned.insert(fan)
            controller = peer
            return true
        case "auto":
            // Only fans this helper took: never flips a fan another app is driving.
            restore(fan < 0 ? nil : owned.intersection([fan]))
            return true
        case "ping":
            return true
        default:
            return false
        }
    }

    static func accept(_ peer: xpc_connection_t) {
        guard xpc_get_type(peer) == XPC_TYPE_CONNECTION else { return }
        guard let requirement, xpc_connection_set_peer_code_signing_requirement(peer, requirement) == 0 else {
            xpc_connection_cancel(peer)
            return
        }
        xpc_connection_set_target_queue(peer, .main)
        xpc_connection_set_event_handler(peer) { m in MainActor.assumeIsolated { receive(m, from: peer) } }
        xpc_connection_activate(peer)
    }

    static func receive(_ m: xpc_object_t, from peer: xpc_connection_t) {
        if xpc_get_type(m) == XPC_TYPE_ERROR {
            // Dylan quit or crashed (or a rejected peer, which never owned anything).
            if let c = controller, c === peer { restore(); controller = nil }
            return
        }
        guard xpc_get_type(m) == XPC_TYPE_DICTIONARY else { return }
        lastMessage = Date()
        let ok = handle(m, from: peer)
        if let reply = xpc_dictionary_create_reply(m) {
            xpc_dictionary_set_bool(reply, "ok", ok)
            xpc_connection_send_message(peer, reply)
        }
    }

    static func tick() {
        if !owned.isEmpty, Date().timeIntervalSince(lastMessage) > FanHelperAPI.watchdog { restore() }
    }
}

Helper.recover()

let listener = xpc_connection_create_mach_service(FanHelperAPI.label, .main, UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER))
xpc_connection_set_event_handler(listener) { peer in MainActor.assumeIsolated { Helper.accept(peer) } }
xpc_connection_activate(listener)

let watchdog = DispatchSource.makeTimerSource(queue: .main)
watchdog.schedule(deadline: .now() + 2, repeating: 2)
watchdog.setEventHandler { MainActor.assumeIsolated { Helper.tick() } }
watchdog.resume()

signal(SIGTERM, SIG_IGN)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
term.setEventHandler { MainActor.assumeIsolated { Helper.restore(); exit(0) } }
term.resume()

dispatchMain()
