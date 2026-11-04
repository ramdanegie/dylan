import Foundation

/// Text screen for the quick terminal (FR-41): a line buffer fed with PTY output. Handles \r, \n, \b, tabs,
/// erase-in-line / clear-screen, and drops other escape sequences (colors, cursor moves, OSC titles).
/// Full-screen programs (vim, htop) are handed off to Terminal instead.
public struct TerminalBuffer: Equatable, Sendable {
    public let maxLines: Int
    /// Long lines wrap here, so one huge line (a minified bundle) costs linear time, not quadratic.
    public static let maxColumns = 2_000
    /// An escape sequence that never ends is dropped after this many bytes instead of holding output back.
    public static let maxPending = 4_096
    private var done: [String] = []
    private var current: [Character] = []
    private var col = 0
    private var pending: [UInt8] = []   // an escape sequence or UTF-8 sequence split across reads

    public init(maxLines: Int = 500) { self.maxLines = maxLines }

    public var lines: [String] { done + [String(current)] }
    public var text: String { lines.joined(separator: "\n") }

    private mutating func newline() {
        done.append(String(current)); current = []; col = 0
        if done.count >= maxLines { done.removeFirst(done.count - maxLines + 1) }
    }

    private mutating func put(_ ch: Character) {
        if col >= Self.maxColumns { newline() }
        if col < current.count { current[col] = ch } else {
            if col > current.count { current += Array(repeating: " ", count: col - current.count) }
            current.append(ch)
        }
        col += 1
    }

    public mutating func append(_ data: Data) {
        let bytes = pending + data
        pending = []
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            switch b {
            case 0x1B:   // ESC
                guard let end = Self.escapeEnd(bytes, from: i) else {
                    if bytes.count - i <= Self.maxPending { pending = Array(bytes[i...]); return }
                    i += 1; continue   // unterminated: drop the ESC, show the rest as text
                }
                let seq = bytes[i..<end]
                if seq.count >= 3, seq[seq.startIndex + 1] == UInt8(ascii: "[") {
                    let final = seq.last!
                    let params = String(decoding: seq.dropFirst(2).dropLast(), as: UTF8.self)
                    if final == UInt8(ascii: "K") {   // erase in line
                        if params.isEmpty || params == "0" { current = Array(current.prefix(col)) }
                        else if params == "2" { current = []; col = 0 }
                    } else if final == UInt8(ascii: "J"), params == "2" || params == "3" {
                        done = []; current = []; col = 0
                    }
                }
                i = end
            case 0x0A: newline(); i += 1
            case 0x0D: col = 0; i += 1
            case 0x08: col = max(0, col - 1); i += 1
            case 0x09: for _ in 0..<(8 - col % 8) { put(" ") }; i += 1
            case 0x07, 0x00: i += 1
            case 0x20...0x7E: put(Character(UnicodeScalar(b))); i += 1
            case 0xC0...0xFF:
                let len = b >= 0xF0 ? 4 : (b >= 0xE0 ? 3 : 2)
                guard i + len <= bytes.count else { pending = Array(bytes[i...]); return }
                for ch in String(decoding: bytes[i..<i + len], as: UTF8.self) { put(ch) }
                i += len
            default: i += 1
            }
        }
    }

    /// End index (exclusive) of the escape sequence at `i`, or nil when it continues in the next read.
    static func escapeEnd(_ b: [UInt8], from i: Int) -> Int? {
        guard i + 1 < b.count else { return nil }
        switch b[i + 1] {
        case UInt8(ascii: "["):   // CSI: parameters, then a final byte 0x40–0x7E
            var j = i + 2
            while j < b.count { if (0x40...0x7E).contains(b[j]) { return j + 1 }; j += 1 }
            return nil
        case UInt8(ascii: "]"):   // OSC: until BEL or ESC \
            var j = i + 2
            while j < b.count {
                if b[j] == 0x07 { return j + 1 }
                if b[j] == 0x1B, j + 1 < b.count, b[j + 1] == UInt8(ascii: "\\") { return j + 2 }
                j += 1
            }
            return nil
        case UInt8(ascii: "("), UInt8(ascii: ")"): return i + 3 <= b.count ? i + 3 : nil
        default: return i + 2
        }
    }
}
