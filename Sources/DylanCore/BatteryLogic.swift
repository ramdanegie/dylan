import Foundation

/// Turns successive power-source snapshots into notch events. FR-70, PRD §F19.
public struct BatterySnapshot: Equatable, Sendable {
    public var percent: Int
    public var isCharging: Bool
    public var onAC: Bool
    /// Minutes until full while charging, if macOS knows.
    public var minutesToFull: Int?
    public var lowPowerMode: Bool
    public init(percent: Int, isCharging: Bool, onAC: Bool, minutesToFull: Int? = nil, lowPowerMode: Bool = false) {
        self.percent = percent; self.isCharging = isCharging; self.onAC = onAC
        self.minutesToFull = minutesToFull; self.lowPowerMode = lowPowerMode
    }
}

public enum BatteryEvent: Equatable, Sendable {
    case pluggedIn, unplugged, full, low20, low10
}

public enum BatteryLogic {
    /// Events caused by going from `old` to `new`. Low warnings fire once when crossing down, on battery only.
    public static func events(from old: BatterySnapshot?, to new: BatterySnapshot) -> [BatteryEvent] {
        guard let old else { return [] }
        var out: [BatteryEvent] = []
        if new.onAC && !old.onAC { out.append(.pluggedIn) }
        if !new.onAC && old.onAC { out.append(.unplugged) }
        if new.onAC && new.percent >= 100 && old.percent < 100 { out.append(.full) }
        if !new.onAC {
            if new.percent <= 10 && old.percent > 10 { out.append(.low10) }
            else if new.percent <= 20 && old.percent > 20 { out.append(.low20) }
        }
        return out
    }
}
