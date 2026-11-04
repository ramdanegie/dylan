import AppKit
import DylanCore

/// Quick terminal in the notch (FR-41): your login shell on a real PTY, opened with ⌃⌥T. Line-based, without a
/// full VT100 screen; full-screen programs (vim, htop) are handed to Terminal or VS Code in the same folder.
/// Like any terminal app, commands run here with Dylan's macOS permissions (e.g. Accessibility).
@Observable
final class TerminalProvider {
    static let shared = TerminalProvider()

    var lines: [String] = []
    var running = false
    @ObservationIgnored private var pty: PTY?
    @ObservationIgnored private let sink = Sink()

    /// PTY output arrives on the reader thread; the view refreshes at most 20 times a second.
    nonisolated final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = TerminalBuffer(maxLines: 400)
        private var scheduled = false
        func append(_ d: Data) -> Bool {
            lock.lock(); defer { lock.unlock() }
            buffer.append(d)
            if scheduled { return false }
            scheduled = true
            return true
        }
        func take() -> [String] { lock.lock(); defer { lock.unlock() }; scheduled = false; return buffer.lines }
        func reset() { lock.lock(); buffer = TerminalBuffer(maxLines: 400); lock.unlock() }
    }

    func start() {
        guard pty == nil else { return }
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil } ?? "/bin/zsh"
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"                 // no line editor or cursor tricks: Dylan shows lines
        env["DYLAN_TERMINAL"] = "1"
        env["PAGER"] = "cat"; env["GIT_PAGER"] = "cat"
        guard let p = PTY(path: shell, args: ["-il"], environment: env, cwd: FileManager.default.homeDirectoryForCurrentUser.path) else {
            lines = [L("terminal.failed")]; return
        }
        pty = p
        running = true
        sink.reset()
        let sink = self.sink
        Thread.detachNewThread {
            p.readLoop { data in
                guard sink.append(data) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    MainActor.assumeIsolated { TerminalProvider.shared.lines = sink.take() }
                }
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { TerminalProvider.shared.exited(p) } }
        }
    }

    private func exited(_ p: PTY) {
        guard pty === p else { return }
        pty = nil
        running = false
        lines = sink.take() + [L("terminal.exited")]
    }

    func send(_ line: String) {
        if pty == nil { start() }
        pty?.write(Data((line + "\n").utf8))
    }

    func interrupt() { pty?.write(Data([0x03])) }

    func clear() { sink.reset(); lines = [] }

    func stop() {
        pty?.terminate(); pty = nil
        running = false
        sink.reset(); lines = []
    }

    /// Hands the session's folder to Terminal or VS Code.
    func handOff(toVSCode: Bool) {
        let dir = pty?.currentDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
        let ws = NSWorkspace.shared
        let ids = toVSCode ? ["com.microsoft.VSCode"] : ["com.apple.Terminal"]
        guard let app = ids.lazy.compactMap({ ws.urlForApplication(withBundleIdentifier: $0) }).first else { return }
        ws.open([URL(fileURLWithPath: dir, isDirectory: true)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    var vsCodeInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") != nil }
}
