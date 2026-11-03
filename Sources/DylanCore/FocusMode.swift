import Foundation

/// Focus on/off from `~/Library/DoNotDisturb/DB` (FR-72, design D32). There is no public API for another
/// app's Focus on macOS; these JSON files are what Control Center writes. Read-only, no private frameworks.
public enum FocusMode {
    public struct Mode: Equatable, Sendable {
        public var id: String
        public var name: String?
        public var symbol: String?
    }

    /// The active Focus, or nil when none is on. `modes` (ModeConfigurations.json) supplies the name and symbol.
    public static func active(assertions: Data, modes: Data?) -> Mode? {
        guard let root = try? JSONSerialization.jsonObject(with: assertions) as? [String: Any],
              let store = (root["data"] as? [[String: Any]])?.first,
              let records = store["storeAssertionRecords"] as? [[String: Any]], !records.isEmpty else { return nil }
        let newest = records.max { start($0) < start($1) }
        guard let details = newest?["assertionDetails"] as? [String: Any],
              let id = details["assertionDetailsModeIdentifier"] as? String else { return nil }
        let config = modes.flatMap { modeConfig(id, $0) }
        return Mode(id: id, name: config?["name"] as? String, symbol: config?["symbolImageName"] as? String)
    }

    static func start(_ r: [String: Any]) -> Double { r["assertionStartDateTimestamp"] as? Double ?? 0 }

    static func modeConfig(_ id: String, _ data: Data) -> [String: Any]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let configs = ((root["data"] as? [[String: Any]])?.first)?["modeConfigurations"] as? [String: Any],
              let entry = configs[id] as? [String: Any] else { return nil }
        return entry["mode"] as? [String: Any]
    }
}
