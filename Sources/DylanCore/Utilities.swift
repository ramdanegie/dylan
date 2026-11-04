import Foundation

// MARK: Keep awake (FR-74, PRD §F19)

/// A keep-awake session: until a time, or until turned off. Stops itself on low battery.
public struct KeepAwake: Equatable, Sendable {
    public var endsAt: Date?
    public var startedAt: Date

    public static func start(duration: TimeInterval?, now: Date) -> KeepAwake {
        KeepAwake(endsAt: duration.map { now.addingTimeInterval($0) }, startedAt: now)
    }

    public func remaining(now: Date) -> TimeInterval? { endsAt.map { max(0, $0.timeIntervalSince(now)) } }

    /// Ends when time is up, or when on battery below the threshold (0 disables the battery rule).
    public func shouldStop(now: Date, battery: BatterySnapshot?, stopBelow: Int) -> Bool {
        if let e = endsAt, now >= e { return true }
        if let b = battery, !b.onAC, stopBelow > 0, b.percent < stopBelow { return true }
        return false
    }
}

// MARK: Color formats (FR-73)

public struct PickedColor: Equatable, Sendable {
    public var r: Double, g: Double, b: Double   // 0…1
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    private func byte(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }

    public var hex: String { String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b)) }
    public var rgb: String { "rgb(\(byte(r)) \(byte(g)) \(byte(b)))" }
    /// CSS-style, as in the design: `16° 100% 60%`.
    public var hsl: String {
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2
        var h = 0.0, s = 0.0
        if mx != mn {
            let d = mx - mn
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            switch mx {
            case r: h = (g - b) / d + (g < b ? 6 : 0)
            case g: h = (b - r) / d + 2
            default: h = (r - g) / d + 4
            }
            h *= 60
        }
        return "\(Int(h.rounded()))° \(Int((s * 100).rounded()))% \(Int((l * 100).rounded()))%"
    }
    /// Developer formats (design D34).
    public var swiftUI: String {
        func f(_ v: Double) -> String { let x = (v * 100).rounded() / 100; return x == x.rounded() ? String(Int(x)) : String(x) }
        return "Color(red: \(f(r)), green: \(f(g)), blue: \(f(b)))"
    }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }
}

// MARK: Touch ID for sudo (FR-29, PRD §F16)

public enum TouchIDSudo {
    /// The command the user runs themselves (Dylan never writes to /etc).
    public static let enableCommand = "sed 's/^#auth/auth/' /etc/pam.d/sudo_local.template | sudo tee /etc/pam.d/sudo_local"

    /// Enabled when an uncommented `auth … pam_tid.so` line exists in /etc/pam.d/sudo_local.
    public static func isEnabled(sudoLocal: String?) -> Bool {
        guard let sudoLocal else { return false }
        return sudoLocal.split(whereSeparator: \.isNewline).contains { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !t.hasPrefix("#") && t.hasPrefix("auth") && t.contains("pam_tid.so")
        }
    }

    /// Touch ID does not show inside tmux/screen without pam_reattach.
    public static func needsReattach(sudoLocal: String?, multiplexerRunning: Bool) -> Bool {
        multiplexerRunning && !(sudoLocal ?? "").contains("pam_reattach")
    }
}
