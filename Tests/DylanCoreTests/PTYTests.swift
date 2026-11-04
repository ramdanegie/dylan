import Foundation
import Testing
@testable import DylanCore

@Suite struct PTYTests {
    final class Sink: @unchecked Sendable {
        let lock = NSLock()
        var buffer = TerminalBuffer()
        func add(_ d: Data) { lock.lock(); buffer.append(d); lock.unlock() }
        var text: String { lock.lock(); defer { lock.unlock() }; return buffer.text }
    }

    func start(_ script: String, cwd: String = "/tmp") throws -> (PTY, Sink, Thread) {
        let pty = try #require(PTY(path: "/bin/sh", args: ["-c", script], environment: ["TERM": "dumb", "PATH": "/usr/bin:/bin"], cwd: cwd))
        let sink = Sink()
        let t = Thread { pty.readLoop { sink.add($0) } }
        t.start()
        return (pty, sink, t)
    }

    func waitFor(_ sink: Sink, _ s: String, timeout: TimeInterval = 5) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if sink.text.contains(s) { return true }; usleep(20_000) }
        return false
    }

    @Test func runsWithAControllingTTYInTheGivenDirectory() throws {
        let (_, sink, _) = try start("tty; ps -o tty= -p $$; pwd; stty size; echo DONE")
        #expect(waitFor(sink, "DONE"))
        let lines = sink.text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.first?.hasPrefix("/dev/ttys") == true)
        #expect(lines.dropFirst().first?.hasPrefix("ttys") == true)   // controlling terminal set
        #expect(lines.contains("/private/tmp") || lines.contains("/tmp"))
        #expect(lines.contains("14 90"))   // rows cols
    }

    @Test func ctrlCInterruptsTheForegroundJob() throws {
        let (pty, sink, _) = try start("trap 'echo GOT_INT; exit 0' INT; echo READY; while :; do sleep 0.1; done")
        #expect(waitFor(sink, "READY"))
        pty.write(Data([0x03]))
        #expect(waitFor(sink, "GOT_INT"))
    }

    /// The real case: an interactive zsh (macOS's default shell) must own the terminal, or Ctrl-C does nothing.
    @Test func interactiveZshOwnsTheTerminalAndCtrlCStopsAJob() throws {
        let pty = try #require(PTY(path: "/bin/zsh", args: ["-f", "-i"], environment: ["PATH": "/usr/bin:/bin", "TERM": "dumb"], cwd: "/tmp"))
        let sink = Sink()
        Thread { pty.readLoop { sink.add($0) } }.start()
        pty.write(Data("ps -o tty= -p $$\n".utf8))
        #expect(waitFor(sink, "ttys"))
        pty.write(Data("sleep 30\n".utf8))
        usleep(500_000)
        pty.write(Data([0x03]))
        // Ctrl-C ends the whole command line in zsh, so ask for the status on the next one.
        pty.write(Data("echo AFTER-$?\n".utf8))
        #expect(waitFor(sink, "AFTER-130"))   // sleep was interrupted (128 + SIGINT)
        pty.terminate()
    }

    @Test func inputAndDirectory() throws {
        let (pty, sink, _) = try start("read x; echo \"got:$x\"; cd /usr; sleep 2", cwd: "/")
        pty.write(Data("hello\n".utf8))
        #expect(waitFor(sink, "got:hello"))
        usleep(200_000)
        #expect(pty.currentDirectory == "/usr")
        pty.terminate()
    }
}

@Suite struct PTYTerminateTests {
    @Test func terminateEndsTheShellAndItsJobs() throws {
        let pty = try #require(PTY(path: "/bin/sh", args: ["-c", "trap '' HUP; sleep 30 & wait"], environment: ["PATH": "/usr/bin:/bin"], cwd: "/tmp"))
        let done = DispatchSemaphore(value: 0)
        Thread { pty.readLoop { _ in }; done.signal() }.start()
        usleep(200_000)
        pty.terminate()
        // HUP is ignored by the script, so this needs the SIGKILL fallback.
        #expect(done.wait(timeout: .now() + 5) == .success)
    }
}
