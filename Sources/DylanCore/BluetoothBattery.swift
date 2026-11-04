import Foundation

/// AirPods and other Bluetooth battery levels from `system_profiler SPBluetoothDataType -json` (FR-44, spike T0.6).
/// Public tool, no private IOBluetooth selectors. Keys: device_batteryLevelLeft/Right/Case for AirPods,
/// device_batteryLevelMain for single-battery devices (headphones, mice, keyboards).
public enum BluetoothBattery {
    public struct Levels: Equatable, Sendable {
        public var left: Int?, right: Int?, case_: Int?, main: Int?
        public var isEmpty: Bool { left == nil && right == nil && case_ == nil && main == nil }
    }

    /// Connected devices only, keyed by address in `AA-BB-CC-DD-EE-FF` form (IOBluetooth's `addressString`).
    public static func parse(_ data: Data) -> [String: Levels] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [:] }
        var out: [String: Levels] = [:]
        for c in controllers {
            for case let dev as [String: [String: Any]] in (c["device_connected"] as? [Any] ?? []) {
                for (_, info) in dev {
                    guard let addr = info["device_address"] as? String else { continue }
                    let l = Levels(left: percent(info["device_batteryLevelLeft"]), right: percent(info["device_batteryLevelRight"]),
                                   case_: percent(info["device_batteryLevelCase"]), main: percent(info["device_batteryLevelMain"]))
                    if !l.isEmpty { out[normalize(addr)] = l }
                }
            }
        }
        return out
    }

    /// `e5:c2:c4:31:7f:c7` / `E5-C2-…` → `E5-C2-C4-31-7F-C7`.
    public static func normalize(_ address: String) -> String {
        address.uppercased().replacingOccurrences(of: ":", with: "-")
    }

    /// "L 80% R 75% Case 40%" (design M8), or "80%" for one battery. Labels come from the caller (localised).
    public static func summary(_ l: Levels, left: String = "L", right: String = "R", caseLabel: String = "Case") -> String {
        if l.left != nil || l.right != nil || l.case_ != nil {
            return [(left, l.left), (right, l.right), (caseLabel, l.case_)].compactMap { n, v in v.map { "\(n) \($0)%" } }.joined(separator: " ")
        }
        return l.main.map { "\($0)%" } ?? ""
    }

    /// Lowest earbud level, for the short ear value.
    public static func lowest(_ l: Levels) -> Int? { [l.left, l.right].compactMap { $0 }.min() ?? l.main }

    static func percent(_ v: Any?) -> Int? {
        guard let s = v as? String else { return (v as? Int).flatMap { (0...100).contains($0) ? $0 : nil } }
        return Int(s.trimmingCharacters(in: CharacterSet(charactersIn: "% "))).flatMap { (0...100).contains($0) ? $0 : nil }
    }
}
