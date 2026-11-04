import Foundation

/// In-progress browser downloads in ~/Downloads (FR-76, PRD §F20).
public enum DownloadWatcher {
    public enum Browser: String, Sendable { case chrome, firefox, safari }

    public struct Partial: Equatable, Sendable {
        public var path: String
        public var browser: Browser
        /// File name the download will have when done.
        public var finalName: String
    }

    /// Recognises a partial download by its name: `x.dmg.crdownload`, `x.dmg.part`, `x.dmg.download` (a bundle).
    /// Chrome's "Unconfirmed 123.crdownload" has no final name yet.
    public static func classify(_ path: String) -> Partial? {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        let base = (name as NSString).deletingPathExtension
        let browser: Browser
        switch ext {
        case "crdownload": browser = .chrome
        case "part": browser = .firefox
        case "download": browser = .safari
        default: return nil
        }
        guard !base.isEmpty else { return nil }
        let final = base.hasPrefix("Unconfirmed ") ? "Download" : base
        return Partial(path: path, browser: browser, finalName: final)
    }

    /// Safari keeps progress in the bundle's Info.plist.
    public static func safariProgress(infoPlist: Data) -> Double? {
        guard let p = try? PropertyListSerialization.propertyList(from: infoPlist, format: nil) as? [String: Any],
              let done = (p["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.doubleValue,
              let total = (p["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.doubleValue, total > 0 else { return nil }
        return min(1, done / total)
    }

    /// A download finished when its partial file is gone and the final file exists next to it.
    public static func finishedPath(_ p: Partial, exists: (String) -> Bool) -> String? {
        guard !exists(p.path) else { return nil }
        let final = ((p.path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(p.finalName)
        return exists(final) ? final : nil
    }
}
