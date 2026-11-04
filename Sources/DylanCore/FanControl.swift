import Foundation

/// Fan presets (FR-96, design D45/D46). `auto` leaves the fans to macOS.
public enum FanPreset: String, CaseIterable, Codable, Sendable {
    case auto, quiet, balanced, performance, max, curve

    /// Fan speed as a fraction of the factory range for a CPU temperature (°C). nil = macOS decides.
    /// Formulas from the design: Quiet ≤ 25 %, Balanced from 50 °C, Performance ≥ 40 %, Max 100 %.
    public func fraction(cpu t: Double) -> Double? {
        let pct: Double
        switch self {
        case .auto, .curve: return nil
        case .quiet: pct = Swift.min(25, Swift.max(0, (t - 60) * 1.2))
        case .balanced: pct = Swift.max(8, (t - 50) * 1.6)
        case .performance: pct = Swift.max(40, (t - 40) * 1.6)
        case .max: pct = 100
        }
        return Swift.min(100, pct) / 100
    }

    /// ⌃⌥⇧0–4 (D46); Curve has no shortcut.
    public static let shortcuts: [FanPreset] = [.auto, .quiet, .balanced, .performance, .max]
}

/// Per-fan mode in Settings (D48).
public enum FanMode: String, CaseIterable, Codable, Sendable { case auto, fixed, curve }

/// Four-point curve on fixed temperatures (D48). Percent stays monotonic as the user drags a point.
public struct FanCurve: Equatable, Codable, Sendable {
    public static let temps: [Double] = [40, 60, 75, 90]
    public static let standard = FanCurve(percents: [10, 30, 65, 100])
    public private(set) var percents: [Double]

    public init(percents: [Double]) {
        precondition(percents.count == 4)
        self.percents = percents
    }

    public func percent(at t: Double) -> Double {
        let T = Self.temps
        if t <= T[0] { return percents[0] }
        if t >= T[3] { return percents[3] }
        for i in 0..<3 where t <= T[i + 1] {
            let k = (t - T[i]) / (T[i + 1] - T[i])
            return percents[i] + k * (percents[i + 1] - percents[i])
        }
        return 100
    }

    /// Moves one point; points above never drop below it and points below never rise above it.
    public mutating func set(_ i: Int, _ v: Double) {
        let v = min(100, max(0, v))
        percents[i] = v
        for j in (i + 1)..<4 { percents[j] = max(percents[j], v) }
        for j in stride(from: i - 1, through: 0, by: -1) { percents[j] = min(percents[j], v) }
    }
}

public enum FanMath {
    /// RPM for a fraction of the factory range, rounded to 10 rpm.
    public static func rpm(_ fraction: Double, min lo: Double, max hi: Double) -> Double {
        let f = Swift.min(1, Swift.max(0, fraction))
        return ((lo + (hi - lo) * f) / 10).rounded() * 10
    }

    public static func fahrenheit(_ c: Double) -> Double { c * 9 / 5 + 32 }

    /// "Normal" < 80 ≤ "Hangat" < 90 ≤ "Panas" (D45 colors).
    public enum Heat: Sendable { case normal, warm, hot }
    public static func heat(_ c: Double) -> Heat { c >= 90 ? .hot : c >= 80 ? .warm : .normal }
}

/// Moving average over a time window: "Halus" response (D48) so the fans do not hunt.
public struct Smoother: Sendable {
    public var window: TimeInterval
    private var samples: [(Date, Double)] = []
    public init(window: TimeInterval) { self.window = window }

    public mutating func add(_ v: Double, at now: Date) -> Double {
        samples.append((now, v))
        samples.removeAll { now.timeIntervalSince($0.0) > window }
        return samples.map(\.1).reduce(0, +) / Double(samples.count)
    }
}

/// Over-temperature warning (FR-97): fires once after `threshold` holds for 30 s, then waits 15 min.
/// Return-to-auto: CPU below 65 °C for 5 min.
public struct HeatWatch: Sendable {
    public var threshold: Double
    public static let hold: TimeInterval = 30
    public static let cooldown: TimeInterval = 15 * 60
    public static let coolTemp: Double = 65
    public static let coolHold: TimeInterval = 5 * 60

    private var hotSince: Date?
    private var lastFired: Date?
    private var coolSince: Date?

    public init(threshold: Double = 95) { self.threshold = threshold }

    /// true once when the warning should show.
    public mutating func overheated(_ t: Double, at now: Date) -> Bool {
        guard t >= threshold else { hotSince = nil; return false }
        let since = hotSince ?? now
        hotSince = since
        guard now.timeIntervalSince(since) >= Self.hold else { return false }
        if let l = lastFired, now.timeIntervalSince(l) < Self.cooldown { return false }
        lastFired = now
        return true
    }

    /// true once the CPU has stayed cool long enough to hand the fans back to macOS.
    public mutating func cooledDown(_ t: Double, at now: Date) -> Bool {
        guard t < Self.coolTemp else { coolSince = nil; return false }
        let since = coolSince ?? now
        coolSince = since
        guard now.timeIntervalSince(since) >= Self.coolHold else { return false }
        coolSince = nil
        return true
    }
}

/// Groups IOHID temperature sensors by their Apple names (M1–M4 use the same PMU names).
public enum ThermalSensors {
    public enum Group: String, CaseIterable, Sendable { case cpu, gpu, ssd, battery }

    public static func group(_ name: String) -> Group? {
        if name.hasPrefix("PMU tdie") { return .cpu }
        if name.hasPrefix("PMU TP"), name.hasSuffix("g") { return .gpu }
        if name.hasPrefix("NAND") { return .ssd }
        if name.hasPrefix("gas gauge battery") { return .battery }
        return nil
    }

    /// Hottest reading per group; implausible values (sensor glitches) are ignored.
    public static func summarize(_ readings: [(String, Double)]) -> [Group: Double] {
        var out: [Group: Double] = [:]
        for (n, v) in readings where v > 5 && v < 130 {
            guard let g = group(n) else { continue }
            out[g] = max(out[g] ?? v, v)
        }
        return out
    }
}
