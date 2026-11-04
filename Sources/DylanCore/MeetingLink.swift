import Foundation

/// Finds a Zoom / Google Meet / Teams link in an event's URL, location or notes. PRD §F6.
public struct MeetingLink: Equatable, Sendable {
    public enum Service: String, Sendable { case zoom, meet, teams }
    public var service: Service
    public var url: URL

    /// For Zoom, the native app URL (`zoommtg://`) so Join skips the browser.
    public var appURL: URL? {
        guard service == .zoom, let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = comps.path.split(separator: "/").last(where: { $0.allSatisfy(\.isNumber) }) else { return nil }
        var out = URLComponents()
        out.scheme = "zoommtg"
        out.host = "zoom.us"
        out.path = "/join"
        var items = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: String(id))]
        if let pwd = comps.queryItems?.first(where: { $0.name == "pwd" })?.value {
            items.append(URLQueryItem(name: "pwd", value: pwd))
        }
        out.queryItems = items
        return out.url
    }

    private static let patterns: [(Service, String)] = [
        (.zoom, #"https://(?:[a-z0-9-]+\.)?zoom\.us/(?:j|my|w)/[^\s<>"')\]]+"#),
        (.meet, #"https://meet\.google\.com/[a-z]{3,4}-[a-z]{4}-[a-z]{3,4}(?:\?[^\s<>"')\]]*)?"#),
        (.teams, #"https://teams\.(?:microsoft|live)\.com/(?:l/meetup-join|meet)/[^\s<>"')\]]+"#),
    ]

    /// Searches the fields in order (event URL first) and returns the first link found.
    public static func find(in fields: [String?]) -> MeetingLink? {
        for field in fields.compactMap({ $0 }) {
            var best: (range: Range<String.Index>, link: MeetingLink)?
            for (service, pattern) in patterns {
                guard let r = field.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
                      let url = URL(string: String(field[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))) else { continue }
                if best == nil || r.lowerBound < best!.range.lowerBound { best = (r, MeetingLink(service: service, url: url)) }
            }
            if let best { return best.link }
        }
        return nil
    }
}
