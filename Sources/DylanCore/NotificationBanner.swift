import Foundation

/// A Notification Center banner read through Accessibility (FR-68/69/82, spike T3.5). On macOS 27 a banner is an
/// AXGroup (subrole AXNotificationCenterBanner) whose description is "App, title[, subtitle], body", with
/// AXStaticText children identified title/subtitle/body and named actions ("Close", "Show", "Reply", …).
public struct NotificationBanner: Equatable, Sendable {
    public var id: String
    public var app: String
    public var title: String
    public var subtitle: String?
    public var body: String
    /// AX action names without the "Name:" wrapper, e.g. ["Show Details", "Show", "Close"].
    public var actions: [String]

    public var canReply: Bool { actions.contains { Self.replyNames.contains($0.lowercased()) } }
    public var isCall: Bool { acceptAction != nil && declineAction != nil }
    public var acceptAction: String? { actions.first { Self.acceptNames.contains($0.lowercased()) } }
    public var declineAction: String? { actions.first { Self.declineNames.contains($0.lowercased()) } }
    public var replyAction: String? { actions.first { Self.replyNames.contains($0.lowercased()) } }
    public var closeAction: String? { actions.first { ["close", "tutup", "clear"].contains($0.lowercased()) } }

    static let replyNames: Set<String> = ["reply", "balas"]
    static let acceptNames: Set<String> = ["accept", "answer", "terima", "jawab"]
    static let declineNames: Set<String> = ["decline", "tolak"]

    /// Builds a banner from the AX values; nil when there is no title and no body.
    public init?(id: String, description: String?, title: String?, subtitle: String?, body: String?, actionNames: [String]) {
        let t = title ?? "", b = body ?? ""
        guard !id.isEmpty, !(t.isEmpty && b.isEmpty) else { return nil }
        self.id = id
        self.title = t
        self.subtitle = subtitle.flatMap { $0.isEmpty ? nil : $0 }
        self.body = b
        self.actions = actionNames.map(Self.actionName)
        app = Self.appName(description: description, title: t, body: b) ?? ""
    }

    /// "Name:Close\nTarget:0x0\nSelector:(null)" → "Close"; plain names pass through.
    public static func actionName(_ raw: String) -> String {
        guard raw.hasPrefix("Name:") else { return raw }
        return String(raw.dropFirst(5).prefix { $0 != "\n" })
    }

    /// The app is what comes before ", <title>" (or ", <body>") in the description.
    static func appName(description: String?, title: String, body: String) -> String? {
        guard let d = description, !d.isEmpty else { return nil }
        for marker in [title, body] where !marker.isEmpty {
            if let r = d.range(of: ", " + marker) { return String(d[..<r.lowerBound]) }
        }
        return d.components(separatedBy: ", ").first
    }
}

/// Which banners Dylan shows (FR-68): an allow-list of app names; empty = every app. Calls always pass.
public enum NotificationRules {
    public static let defaultApps = ["Messages", "Pesan", "WhatsApp", "Telegram", "Slack", "Mail", "Microsoft Teams", "Discord", "FaceTime"]

    public static func allowed(_ b: NotificationBanner, apps: [String]) -> Bool {
        if b.isCall { return true }
        let list = apps.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        return list.isEmpty || list.contains(b.app.lowercased())
    }

    /// "Rani · Slide sprint review …" (title, then body), one line.
    public static func detail(_ b: NotificationBanner) -> String {
        [b.title, b.subtitle, b.body].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
