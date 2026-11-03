import Foundation

/// Other players (FR-11) without MediaRemote: the browser tab that plays (title + URL through AppleScript) and
/// VLC's own AppleScript. Playing state comes from Core Audio (the browser is producing sound).
public enum BrowserMedia {
    public struct Item: Equatable, Sendable {
        public var title: String
        public var artist: String
        public var site: String
    }

    public static let browsers: [String: String] = [
        "com.google.Chrome": "Chrome", "com.apple.Safari": "Safari", "company.thebrowser.Browser": "Arc",
        "com.microsoft.edgemac": "Edge", "com.brave.Browser": "Brave", "com.vivaldi.Vivaldi": "Vivaldi",
    ]

    /// The first tab that is a media page, cleaned up ("(3) Lagu - YouTube" → "Lagu", site "YouTube").
    public static func pick(_ tabs: [(title: String, url: String)]) -> Item? {
        for t in tabs { if let i = item(title: t.title, url: t.url) { return i } }
        return nil
    }

    /// Page titles that are a site's own name or navigation, not something playing.
    static let notMedia: Set<String> = ["youtube", "youtube music", "soundcloud", "stream", "discover", "feed", "home", "library",
                                        "twitch", "browse", "following", "apple music", "apple music - web player", "netflix", "spotify"]

    static func item(title raw: String, url: String) -> Item? {
        guard let found = parse(title: raw, url: url), !notMedia.contains(found.title.lowercased()) else { return nil }
        return found
    }

    private static func parse(title raw: String, url: String) -> Item? {
        guard let u = URL(string: url), let host = u.host?.lowercased() else { return nil }
        let path = u.path.split(separator: "/")
        // Unread counts some sites put in front: "(3) Title".
        var title = raw.replacingOccurrences(of: #"^\(\d+\)\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        func strip(_ suffix: String) { if title.hasSuffix(suffix) { title = String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces) } }
        switch true {
        case host == "music.youtube.com" && url.contains("/watch"):
            strip("- YouTube Music")
            return title.isEmpty ? nil : Item(title: title, artist: "", site: "YouTube Music")
        case host.hasSuffix("youtube.com") && (url.contains("/watch") || url.contains("/shorts/") || url.contains("/live")),
             host == "youtu.be":
            strip("- YouTube")
            return title.isEmpty ? nil : Item(title: title, artist: "", site: "YouTube")
        case host.hasSuffix("soundcloud.com") && path.count >= 2:   // /artist/track, not /discover or /stream
            strip("| Listen online for free on SoundCloud"); strip("| SoundCloud")
            if title.hasPrefix("Stream ") { title = String(title.dropFirst(7)) }
            if let r = title.range(of: " by ", options: .backwards) {
                return Item(title: String(title[r.upperBound...]).isEmpty ? title : String(title[..<r.lowerBound]),
                            artist: String(title[r.upperBound...]), site: "SoundCloud")
            }
            return title.isEmpty ? nil : Item(title: title, artist: "", site: "SoundCloud")
        case host == "open.spotify.com":
            // "Song • Artist"
            let parts = title.components(separatedBy: " • ")
            guard parts.count >= 2 else { return nil }
            return Item(title: parts[0], artist: parts[1], site: "Spotify Web")
        case host.hasSuffix("twitch.tv") && path.count == 1 && !["directory", "videos", "search"].contains(String(path[0])):
            strip("- Twitch")
            return title.isEmpty || title == "Twitch" ? nil : Item(title: title, artist: "", site: "Twitch")
        case host.hasSuffix("netflix.com") && url.contains("/watch"):
            return Item(title: title.isEmpty ? "Netflix" : title, artist: "", site: "Netflix")
        case host == "music.apple.com" && path.contains(where: { ["song", "album", "playlist", "station"].contains(String($0)) }):
            strip("- Apple Music")
            return title.isEmpty ? nil : Item(title: title, artist: "", site: "Apple Music Web")
        default:
            return nil
        }
    }

    /// AppleScript: one line per tab, "title<TAB>url", front window first. Chrome-family and Safari differ.
    public static func tabsScript(bundleID: String) -> String {
        let titleProp = bundleID == "com.apple.Safari" ? "name" : "title"
        return """
        set out to ""
        tell application id "\(bundleID)"
            repeat with w in windows
                repeat with t in tabs of w
                    set out to out & (\(titleProp) of t) & tab & (URL of t) & linefeed
                end repeat
            end repeat
        end tell
        return out
        """
    }

    public static func parseTabs(_ out: String) -> [(title: String, url: String)] {
        out.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            return p.count == 2 ? (String(p[0]), String(p[1])) : nil
        }
    }

    /// VLC: "playing<TAB>name<TAB>duration<TAB>time".
    public static let vlcScript = """
    tell application id "org.videolan.vlc"
        if name of current item is missing value then return ""
        return (playing as text) & tab & (name of current item) & tab & (duration of current item) & tab & (current time)
    end tell
    """

    static let mediaExtensions: Set<String> = ["mp3", "mp4", "m4a", "m4v", "mkv", "mov", "avi", "webm", "flac", "wav", "ogg", "opus",
                                               "aac", "wmv", "mpg", "mpeg", "ts", "3gp"]

    public static func parseVLC(_ out: String) -> (playing: Bool, title: String, duration: Double, position: Double)? {
        let p = out.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard p.count == 4, !p[1].isEmpty else { return nil }
        // Strip only a media file extension VLC keeps in the item name ("Live at 10.30" stays whole).
        let ext = (p[1] as NSString).pathExtension.lowercased()
        let name = mediaExtensions.contains(ext) ? (p[1] as NSString).deletingPathExtension : p[1]
        return (p[0] == "true", name, Double(p[2]) ?? 0, Double(p[3]) ?? 0)
    }
}
