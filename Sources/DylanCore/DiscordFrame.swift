import Foundation

/// Discord local RPC framing (spike T0.5): opcode (UInt32 LE) + length (UInt32 LE) + JSON. PRD §F17.
public struct DiscordFrame: Equatable, Sendable {
    public enum Opcode: UInt32, Sendable { case handshake = 0, frame = 1, close = 2, ping = 3, pong = 4 }

    public var opcode: Opcode
    public var json: Data

    public init(opcode: Opcode, json: Data) { self.opcode = opcode; self.json = json }

    public var encoded: Data {
        var d = Data(capacity: 8 + json.count)
        withUnsafeBytes(of: opcode.rawValue.littleEndian) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(json.count).littleEndian) { d.append(contentsOf: $0) }
        d.append(json)
        return d
    }

    public static func handshake(clientID: String) -> DiscordFrame {
        let body = try? JSONSerialization.data(withJSONObject: ["v": 1, "client_id": clientID], options: [.sortedKeys])
        return DiscordFrame(opcode: .handshake, json: body ?? Data())
    }

    public enum DecodeError: Error, Equatable { case badOpcode(UInt32), tooLarge }

    /// Accumulates socket bytes and yields complete frames.
    public struct Decoder: Sendable {
        private var buffer = Data()
        public static let maxPayload = 1 << 20
        public init() {}

        public mutating func append(_ data: Data) throws -> [DiscordFrame] {
            buffer.append(data)
            var out: [DiscordFrame] = []
            while buffer.count >= 8 {
                let b = [UInt8](buffer.prefix(8))
                let op = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
                let len = Int(UInt32(b[4]) | UInt32(b[5]) << 8 | UInt32(b[6]) << 16 | UInt32(b[7]) << 24)
                guard len <= Self.maxPayload else { buffer.removeAll(); throw DecodeError.tooLarge }
                guard let opcode = Opcode(rawValue: op) else { buffer.removeAll(); throw DecodeError.badOpcode(op) }
                guard buffer.count >= 8 + len else { break }
                let start = buffer.startIndex + 8
                out.append(DiscordFrame(opcode: opcode, json: Data(buffer[start..<(start + len)])))
                buffer.removeSubrange(buffer.startIndex..<(start + len))
            }
            return out
        }
    }
}
