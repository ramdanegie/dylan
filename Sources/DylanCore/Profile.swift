import Foundation

/// Profile Umum / Developer. FR-17.
public enum Profile: String, Codable, Sendable, CaseIterable {
    case general, developer
}

/// Features that can be switched on and off. `[Dev]` features never run under the general profile.
public enum Feature: String, Codable, Sendable, CaseIterable {
    // Everyone
    case media, meeting, timer, battery, bluetooth, privacy, presentation, keepAwake, colorPicker, clipboard, stats, shelf, lyrics, reminders, weather, downloads, mirror, scratchpad, discord, hud, focus
    // Developer Mode
    case agents, commands, cli, ports, docker, github, widgets

    public var isDeveloper: Bool {
        switch self {
        case .agents, .commands, .cli, .ports, .docker, .github, .widgets: return true
        default: return false
        }
    }

    /// Off unless the user turns it on: Bluetooth asks for a permission, lyrics use the network.
    public var defaultOn: Bool { ![.bluetooth, .lyrics, .weather, .downloads, .github, .hud].contains(self) }
}

public struct FeatureSet: Codable, Equatable, Sendable {
    public var profile: Profile
    /// Explicit user choices; missing entries use `Feature.defaultOn`.
    public var toggles: [Feature: Bool]

    public init(profile: Profile = .general, toggles: [Feature: Bool] = [:]) {
        self.profile = profile; self.toggles = toggles
    }

    public func isEnabled(_ f: Feature) -> Bool {
        if f.isDeveloper && profile != .developer { return false }
        return toggles[f] ?? f.defaultOn
    }

    public var enabled: Set<Feature> { Set(Feature.allCases.filter(isEnabled)) }
}

/// Language choice. FR-18. Stored as `AppleLanguages` in Dylan's defaults (same as System Settings per-app language).
public enum LanguageChoice: String, Codable, Sendable, CaseIterable {
    case system, indonesian = "id", english = "en"

    /// Value for the `AppleLanguages` default; nil removes the key so the system language applies.
    public var appleLanguages: [String]? {
        switch self {
        case .system: return nil
        case .indonesian: return ["id"]
        case .english: return ["en"]
        }
    }

    public static func from(appleLanguages: [String]?) -> LanguageChoice {
        guard let first = appleLanguages?.first else { return .system }
        if first.hasPrefix("id") { return .indonesian }
        if first.hasPrefix("en") { return .english }
        return .system
    }

    /// Resolves to a supported UI language: Indonesian if the system prefers it, otherwise English.
    public static func resolve(_ choice: LanguageChoice, systemPreferred: [String]) -> String {
        switch choice {
        case .indonesian: return "id"
        case .english: return "en"
        case .system:
            for l in systemPreferred {
                if l.hasPrefix("id") { return "id" }
                if l.hasPrefix("en") { return "en" }
            }
            return "en"
        }
    }
}
