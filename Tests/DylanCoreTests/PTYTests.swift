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

    @Test func inputAndDirectory() throws {
        let (pty, sink, _) = try start("read x; echo \"got:$x\"; cd /usr; sleep 2", cwd: "/")
        pty.write(Data("hello\n".utf8))
        #expect(waitFor(sink, "got:hello"))
        usleep(200_000)
        #expect(pty.currentDirectory == "/usr")
        pty.terminate()
    }
}
