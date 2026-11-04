import Foundation
import Testing
@testable import DylanCore

@Suite struct TerminalBufferTests {
    func run(_ chunks: [String], max: Int = 500) -> TerminalBuffer {
        var t = TerminalBuffer(maxLines: max)
        for c in chunks { t.append(Data(c.utf8)) }
        return t
    }

    @Test func plainLinesAndColors() {
        #expect(run(["\u{1B}[1;32m✓\u{1B}[0m 12 passed\r\n", "done"]).lines == ["✓ 12 passed", "done"])
        #expect(run(["\u{1B}]0;~/web-admin\u{07}% ls\r\n"]).lines == ["% ls", ""])
    }

    @Test func carriageReturnAndProgress() {
        // npm-style progress bars overwrite the line.
        #expect(run(["10%\r50%\r100%\r\n"]).lines == ["100%", ""])
        #expect(run(["abcdef\r\u{1B}[Kxy"]).lines == ["xy"])
        #expect(run(["abc\u{08}\u{08}X"]).lines == ["aXc"])
        #expect(run(["one\r\ntwo\u{1B}[2J", "fresh"]).lines == ["fresh"])
    }

    @Test func sequencesSplitAcrossReads() {
        #expect(run(["a\u{1B}[3", "1mred\u{1B}[0m"]).lines == ["ared"])
        let e = Array("é".utf8)
        var t = TerminalBuffer()
        t.append(Data([UInt8(ascii: "x"), e[0]])); t.append(Data([e[1]]))
        #expect(t.lines == ["xé"])
    }

    @Test func tabsAndLimit() {
        #expect(run(["a\tb"]).lines == ["a       b"])
        #expect(run([(1...10).map(String.init).joined(separator: "\n")], max: 3).lines == ["8", "9", "10"])
    }

    @Test func hugeLinesAndUnterminatedEscapes() {
        let start = Date()
        var t = TerminalBuffer()
        t.append(Data(String(repeating: "x", count: 50_000).utf8))
        #expect(Date().timeIntervalSince(start) < 1)                       // was quadratic: seconds per line
        #expect(t.lines.allSatisfy { $0.count <= TerminalBuffer.maxColumns })
        var u = TerminalBuffer()
        u.append(Data("\u{1B}]0;never ends".utf8))
        u.append(Data((String(repeating: "y", count: 5_000) + "\nvisible").utf8))
        #expect(u.lines.last == "visible")                                // output is not held back forever
    }
}
