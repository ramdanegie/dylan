import Foundation

/// Settings → Supported features (design D37). One entry per user-facing feature, grouped like the
/// Settings sidebar, written for non-engineers. FR ids are kept for the coverage test only and never shown.
/// Status is derived from what this build actually ships (`built`), not from the roadmap alone.
public struct FeatureSupport: Sendable, Identifiable, Equatable {
    public enum Group: String, Sendable, CaseIterable {
        case notch, media, calendar, devices, communication, files, utilities, security, developer
    }

    public enum Release: Int, Sendable, Comparable, CaseIterable {
        case v1_0 = 10, v1_1 = 11, v1_2 = 12, v1_3 = 13, v2_0 = 20
        public static func < (a: Release, b: Release) -> Bool { a.rawValue < b.rawValue }
    }

    public enum Status: String, Sendable, Equatable {
        /// In this build.
        case available
        /// Not in this build yet, planned for the next release (or unfinished v1.0 scope).
        case soon
        /// Later on the roadmap.
        case planned
        /// Off by default, behind a spike.
        case experimental
        /// Built, but needs a newer macOS than this Mac runs.
        case unsupported
    }

    /// The release this build is working towards. Unbuilt items up to `current + 1` count as "soon".
    public static let current: Release = .v1_0

    /// Slug; UI strings are `support.<id>` (name) and `support.<id>.desc`, plus `support.<id>.req` when `hasRequirement`.
    public let id: String
    public let group: Group
    public let requirements: [String]
    public let release: Release
    public let built: Bool
    public let experimental: Bool
    public let hasRequirement: Bool
    /// Minimum macOS major version for the feature (e.g. 26 for Liquid Glass).
    public let minMacOS: Int?

    init(_ id: String, _ group: Group, _ fr: [Int], _ release: Release, built: Bool = false,
         experimental: Bool = false, req: Bool = false, minMacOS: Int? = nil) {
        self.id = id; self.group = group; requirements = fr.map { "FR-\($0)" }; self.release = release
        self.built = built; self.experimental = experimental; hasRequirement = req; self.minMacOS = minMacOS
    }

    public func status(macOSMajor: Int) -> Status {
        if experimental { return .experimental }
        if built {
            if let m = minMacOS, macOSMajor < m { return .unsupported }
            return .available
        }
        return release <= Self.nextRelease ? .soon : .planned
    }

    static var nextRelease: Release {
        Release.allCases.first { $0 > current } ?? current
    }

    public var isDeveloper: Bool { group == .developer }

    public static let all: [FeatureSupport] = [
        // Notch & Live Activity
        .init("liveActivity", .notch, [1, 2, 3, 4], .v1_0, built: true),
        .init("fullscreen", .notch, [5], .v1_0, built: true),
        .init("presentation", .notch, [16], .v1_0, built: true),
        .init("autoPresentation", .notch, [28], .v1_1, req: true),
        .init("pill", .notch, [27], .v1_1, built: true),
        .init("themes", .notch, [78], .v1_1, built: true, req: true),
        .init("home", .notch, [14], .v1_0, built: true),
        .init("settings", .notch, [15], .v1_0, built: true),
        .init("profile", .notch, [17], .v1_0, built: true),
        .init("language", .notch, [18], .v1_0, built: true),
        // Media
        .init("nowPlaying", .media, [11], .v1_0, built: true),
        .init("otherPlayers", .media, [11], .v1_0, req: true),
        .init("controls", .media, [60], .v1_0, built: true),
        .init("quickPlay", .media, [60], .v1_0, built: true),
        .init("lyrics", .media, [62], .v1_1, built: true, req: true),
        .init("audioOutput", .media, [61], .v1_1, built: true),
        .init("appVolume", .media, [84], .v1_1, built: true, req: true),
        .init("hud", .media, [40], .v1_1, built: true, req: true),
        .init("visualizer", .media, [63], .v1_3, built: true, req: true),
        .init("spotifyAccount", .media, [64], .v1_3, req: true),
        // Calendar & time
        .init("meeting", .calendar, [12], .v1_0, built: true, req: true),
        .init("timer", .calendar, [13], .v1_0, built: true),
        .init("reminders", .calendar, [75], .v1_2, built: true, req: true),
        .init("quickAdd", .calendar, [85], .v1_2, built: true),
        .init("weather", .calendar, [45], .v1_2, built: true, req: true),
        .init("timeToLeave", .calendar, [81], .v1_3, built: true, req: true),
        // Devices & system
        .init("battery", .devices, [70], .v1_0, built: true),
        .init("bluetooth", .devices, [44], .v1_0, built: true, req: true),
        .init("airpodsBattery", .devices, [44], .v1_0, built: true),
        .init("privacy", .devices, [71], .v1_0, built: true),
        .init("keepAwake", .devices, [74], .v1_1, built: true),
        .init("focus", .devices, [72], .v1_1, built: true, req: true),
        .init("stats", .devices, [26], .v1_1, built: true),
        .init("downloads", .devices, [76], .v1_2, built: true),
        // Communication
        .init("discordVoice", .communication, [65, 67], .v1_1, built: true, req: true),
        .init("discordDM", .communication, [66], .v1_1, built: true, req: true),
        .init("notifications", .communication, [68], .v1_2, req: true),
        .init("replies", .communication, [69], .v1_2),
        .init("calls", .communication, [82], .v1_2),
        .init("meetingControls", .communication, [83], .v1_2, built: true, req: true),
        // Files & clipboard
        .init("clipboard", .files, [20], .v1_1, built: true),
        .init("secrets", .files, [22], .v1_1, built: true),
        .init("shelf", .files, [23], .v1_1, built: true),
        .init("screenshotShelf", .files, [24], .v1_1, built: true),
        .init("transforms", .files, [43], .v1_3, built: true),
        .init("removeBackground", .files, [77], .v1_3, built: true, req: true),
        .init("ocr", .files, [87], .v1_3, built: true),
        .init("floatingBasket", .files, [86], .v1_3, built: true),
        // Utilities
        .init("colorPicker", .utilities, [73], .v1_1, built: true),
        .init("scratchpad", .utilities, [46], .v1_3, built: true),
        .init("mirror", .utilities, [79], .v1_3, built: true, req: true),
        .init("lockScreen", .utilities, [80], .v1_3, experimental: true, req: true),
        // Security
        .init("faceUnlock", .security, [50, 51, 52, 53, 54, 55], .v2_0, experimental: true, req: true),
        // Developer
        .init("claudeSessions", .developer, [7, 8], .v1_0, built: true),
        .init("answerFromNotch", .developer, [9], .v1_0, built: true, req: true),
        .init("commands", .developer, [10], .v1_0, built: true, req: true),
        .init("cli", .developer, [6], .v1_0, built: true),
        .init("devTools", .developer, [21], .v1_1, built: true),
        .init("ports", .developer, [25], .v1_1, built: true),
        .init("touchID", .developer, [29], .v1_1, built: true),
        .init("github", .developer, [30], .v1_2, built: true, req: true),
        .init("widgets", .developer, [31], .v1_2, built: true),
        .init("codex", .developer, [32], .v1_2, built: true),
        .init("docker", .developer, [33], .v1_2, built: true),
        .init("otherAgents", .developer, [34], .v1_2, built: true),
        .init("terminal", .developer, [41], .v1_3),
        .init("mcp", .developer, [42], .v1_3, built: true),
    ]
}
