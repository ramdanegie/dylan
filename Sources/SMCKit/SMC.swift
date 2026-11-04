import Foundation
import IOKit

/// The AppleSMC user client (PRD §F24). Reading works for any user; writing needs root, so only the fan helper writes.
/// Layout of SMCKeyData_t (80 bytes): key @0, keyInfo.dataSize @28, keyInfo.dataType @32, result @40, data8 @42,
/// data32 @44, bytes @48. Spike on M1 Pro, macOS 27.2: F<n>Md is ui8 (0 auto, 1 manual), F<n>Ac/Mn/Mx/Tg are
/// little-endian `flt`, and there is no `Ftst` key.
/// One IOKit connection; IOConnectCallStructMethod is safe to call from any thread.
public final class SMC: @unchecked Sendable {
    public struct Fan: Equatable, Sendable {
        public var index: Int
        public var rpm: Double
        public var min: Double
        public var max: Double
        public var manual: Bool
        public var target: Double
        public init(index: Int, rpm: Double, min: Double, max: Double, manual: Bool, target: Double) {
            self.index = index; self.rpm = rpm; self.min = min; self.max = max; self.manual = manual; self.target = target
        }
    }

    private var conn: io_connect_t = 0

    public init?() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        guard IOServiceOpen(svc, mach_task_self_, 0, &conn) == kIOReturnSuccess else { return nil }
    }

    deinit { IOServiceClose(conn) }

    // MARK: Fans

    public var fanCount: Int { read("FNum").flatMap { Self.decode($0.type, $0.bytes) }.map(Int.init) ?? 0 }

    public func fan(_ i: Int) -> Fan? {
        func v(_ k: String) -> Double? { read("F\(i)\(k)").flatMap { Self.decode($0.type, $0.bytes) } }
        guard let rpm = v("Ac"), let lo = v("Mn"), let hi = v("Mx") else { return nil }
        return Fan(index: i, rpm: rpm, min: lo, max: hi, manual: (v("Md") ?? 0) == 1, target: v("Tg") ?? rpm)
    }

    public var fans: [Fan] { (0..<fanCount).compactMap(fan) }

    /// Manual mode at `rpm`, clamped to the factory range. Root only.
    @discardableResult public func setManual(_ i: Int, rpm: Double) -> Bool {
        guard let f = fan(i) else { return false }
        let target = Swift.min(Swift.max(rpm, f.min), f.max)
        return write("F\(i)Md", 1) && write("F\(i)Tg", target)
    }

    /// Back to macOS control. Root only.
    @discardableResult public func setAuto(_ i: Int) -> Bool { write("F\(i)Md", 0) }

    // MARK: Keys

    public func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        var b = Self.request(key, op: 9)
        guard let info = call(b) else { return nil }
        let size = Int(Self.u32(info, 28)), type = Self.string(Self.u32(info, 32))
        guard size > 0, size <= 32 else { return nil }
        b[42] = 5
        Self.put(&b, 28, UInt32(size))
        guard let out = call(b) else { return nil }
        return (type, Array(out[48..<48 + size]))
    }

    public func write(_ key: String, _ value: Double) -> Bool {
        guard let cur = read(key), let bytes = Self.encode(value, type: cur.type), bytes.count == cur.bytes.count else { return false }
        var b = Self.request(key, op: 6)
        Self.put(&b, 28, UInt32(bytes.count))
        for (i, x) in bytes.enumerated() { b[48 + i] = x }
        return call(b) != nil
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var inp = input, out = [UInt8](repeating: 0, count: 80), size = 80
        let r = IOConnectCallStructMethod(conn, 2, &inp, 80, &out, &size)
        return r == kIOReturnSuccess && out[40] == 0 ? out : nil
    }

    // MARK: Codec (pure, tested)

    public static func fourcc(_ s: String) -> UInt32 { s.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) } }
    static func string(_ v: UInt32) -> String { String(bytes: [24, 16, 8, 0].map { UInt8((v >> UInt32($0)) & 0xff) }, encoding: .ascii) ?? "" }

    public static func decode(_ type: String, _ d: [UInt8]) -> Double? {
        switch type {
        case "flt " where d.count == 4: return Double(d.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case "ui8 " where d.count == 1: return Double(d[0])
        case "ui16" where d.count == 2: return Double(UInt16(d[0]) << 8 | UInt16(d[1]))
        case "ui32" where d.count == 4: return Double(d.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        case "sp78" where d.count == 2: return Double(Int16(bitPattern: UInt16(d[0]) << 8 | UInt16(d[1]))) / 256
        case "fpe2" where d.count == 2: return Double(UInt16(d[0]) << 8 | UInt16(d[1])) / 4
        default: return nil
        }
    }

    public static func encode(_ v: Double, type: String) -> [UInt8]? {
        switch type {
        case "flt ": return withUnsafeBytes(of: Float(v)) { Array($0) }
        case "ui8 " where v >= 0 && v <= 255: return [UInt8(v)]
        case "fpe2" where v >= 0 && v < 16384: let x = UInt16(v * 4); return [UInt8(x >> 8), UInt8(x & 0xff)]
        default: return nil
        }
    }

    static func request(_ key: String, op: UInt8) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 80)
        put(&b, 0, fourcc(key))
        b[42] = op
        return b
    }
    static func put(_ b: inout [UInt8], _ off: Int, _ v: UInt32) { withUnsafeBytes(of: v) { for i in 0..<4 { b[off + i] = $0[i] } } }
    static func u32(_ b: [UInt8], _ off: Int) -> UInt32 { b[off..<off + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
}

/// The helper's XPC contract, shared by both sides.
public enum FanHelperAPI {
    public static let label = "io.github.ramdanegie.dylan.fan"
    public static let plist = label + ".plist"
    /// No message for this long while a fan is manual → the helper restores Auto (D49).
    public static let watchdog: TimeInterval = 10
}
