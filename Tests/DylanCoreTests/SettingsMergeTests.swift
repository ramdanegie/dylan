import Foundation
import Testing
@testable import DylanCore

private let cmd = HookInstaller.command(cliPath: "/Applications/Dylan.app/Contents/MacOS/dylan")

private func obj(_ d: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: d) as? [String: Any])
}

@Suite struct SettingsMergeTests {
    @Test func emptyFile() throws {
        let r = try HookInstaller.install(into: nil, command: cmd)
        #expect(r.added == 8)
        let hooks = try #require(try obj(r.json)["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(HookInstaller.events.map(\.name)))
        #expect(try HookInstaller.status(r.json, command: cmd) == .installed)
        let perm = try #require((hooks["PermissionRequest"] as? [[String: Any]])?.first)
        #expect(perm["matcher"] as? String == "*")
        #expect((perm["hooks"] as? [[String: Any]])?.first?["timeout"] as? Int == 60)
    }

    @Test func keepsUserHooksAndSettings() throws {
        let user = #"""
        {"model":"opus","permissions":{"allow":["Bash(npm test)"]},
         "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"~/bin/guard.sh"}]}],
                  "PreCompact":[{"hooks":[{"type":"command","command":"say compact"}]}]}}
        """#
        let r = try HookInstaller.install(into: Data(user.utf8), command: cmd)
        #expect(r.added == 8)
        let o = try obj(r.json)
        #expect(o["model"] as? String == "opus")
        let hooks = try #require(o["hooks"] as? [String: Any])
        let pre = try #require(hooks["PreToolUse"] as? [[String: Any]])
        #expect(pre.count == 2)
        #expect(pre[0]["matcher"] as? String == "Bash")
        #expect(hooks["PreCompact"] != nil)

        // Uninstall returns to the user's original content.
        let u = try HookInstaller.uninstall(from: r.json)
        #expect(u.removed == 8)
        #expect(try HookInstaller.normalized(u.json) == (try HookInstaller.normalized(Data(user.utf8))))
    }

    @Test func idempotent() throws {
        let once = try HookInstaller.install(into: nil, command: cmd)
        let twice = try HookInstaller.install(into: once.json, command: cmd)
        #expect(twice.added == 0 && twice.updated == 0)
        #expect(twice.json == once.json)
    }

    @Test func appMovedUpdatesPath() throws {
        let old = try HookInstaller.install(into: nil, command: HookInstaller.command(cliPath: "/tmp/Dylan.app/Contents/MacOS/dylan"))
        #expect(try HookInstaller.status(old.json, command: cmd) == .needsUpdate)
        let r = try HookInstaller.install(into: old.json, command: cmd)
        #expect(r.added == 0 && r.updated == 8)
        #expect(try HookInstaller.status(r.json, command: cmd) == .installed)
    }

    @Test func rejectsBrokenJSON() {
        #expect(throws: (any Error).self) { try HookInstaller.install(into: Data("{not json".utf8), command: cmd) }
        #expect(throws: HookInstaller.MergeError.notAnObject) { try HookInstaller.install(into: Data("[1]".utf8), command: cmd) }
        #expect(throws: HookInstaller.MergeError.hooksNotAnObject) {
            try HookInstaller.install(into: Data(#"{"hooks":[]}"#.utf8), command: cmd)
        }
        #expect(throws: HookInstaller.MergeError.eventNotAnArray("Stop")) {
            try HookInstaller.install(into: Data(#"{"hooks":{"Stop":{}}}"#.utf8), command: cmd)
        }
    }

    @Test func uninstallWithoutHooksIsNoop() throws {
        let r = try HookInstaller.uninstall(from: Data(#"{"model":"x"}"#.utf8))
        #expect(r.removed == 0)
        #expect(try obj(r.json)["hooks"] == nil)
    }

    @Test func quotesPathsWithSpaces() {
        #expect(HookInstaller.command(cliPath: "/Apps/My Dylan.app/dylan") == "'/Apps/My Dylan.app/dylan' hook claude")
        #expect(cmd == "/Applications/Dylan.app/Contents/MacOS/dylan hook claude")
    }

    @Test func lineDiff() {
        let d = LineDiff.diff(old: "a\nb\nc", new: "a\nx\nc\nd")
        #expect(d == [.same("a"), .removed("b"), .added("x"), .same("c"), .added("d")])
    }
}
