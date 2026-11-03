import Foundation

/// Mute, camera and share for the call in progress (FR-83, design D28). Which app is in a call comes from
/// the microphone user (privacy indicator, D32); controls are the apps' own keyboard shortcuts.
public enum MeetingControls {
    public enum App: String, Sendable, CaseIterable {
        case zoom, teams, meet
        public var name: String {
            switch self { case .zoom: "Zoom"; case .teams: "Teams"; case .meet: "Meet" }
        }
    }

    public enum Control: String, Sendable, CaseIterable { case mic, camera, share }

    public struct Shortcut: Equatable, Sendable {
        public var key: Character
        public var shift = false
        public var option = false
        public var control = false

        /// AXMenuItemCmdModifiers: Shift = 1, Option = 2, Control = 4 (Command is implied; 8 = no Command).
        public var axModifiers: Int { (shift ? 1 : 0) | (option ? 2 : 0) | (control ? 4 : 0) }
    }

    static let browsers: Set<String> = [
        "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.microsoft.edgemac",
        "com.brave.Browser", "org.mozilla.firefox", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    /// `windowTitle` is the browser's focused window title (Accessibility); Meet tabs are titled "Meet - abc-defg-hij".
    public static func app(bundleID: String?, windowTitle: String?) -> App? {
        switch bundleID {
        case "us.zoom.xos": return .zoom
        case "com.microsoft.teams2", "com.microsoft.teams": return .teams
        case let id? where browsers.contains(id):
            guard let t = windowTitle else { return nil }
            return t.hasPrefix("Meet - ") || t.hasPrefix("Meet – ") || t.contains("meet.google.com") ? .meet : nil
        default: return nil
        }
    }

    public static func shortcut(_ app: App, _ c: Control) -> Shortcut? {
        switch (app, c) {
        case (.zoom, .mic): return Shortcut(key: "A", shift: true)
        case (.zoom, .camera): return Shortcut(key: "V", shift: true)
        case (.zoom, .share): return Shortcut(key: "S", shift: true)
        case (.teams, .mic): return Shortcut(key: "M", shift: true)
        case (.teams, .camera): return Shortcut(key: "O", shift: true)
        case (.teams, .share): return Shortcut(key: "E", shift: true)
        case (.meet, .mic): return Shortcut(key: "D")
        case (.meet, .camera): return Shortcut(key: "E")
        case (.meet, .share): return nil   // Meet has no share shortcut
        }
    }

    /// Muted apps may stop the microphone; keep the controls this long after the app last used it.
    public static let grace: TimeInterval = 120
}
