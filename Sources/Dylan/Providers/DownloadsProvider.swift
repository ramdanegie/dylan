import AppKit
import DylanCore

/// Browser downloads in ~/Downloads (FR-76). Directory events wake it up; sizes are read every
/// second only while a partial file exists. Off by default: macOS asks for Downloads access.
final class DownloadsProvider {
    static let shared = DownloadsProvider()

    private struct Tracked { var partial: DownloadWatcher.Partial; var bytes: Int64; var changedAt: Date }
    /// A partial file that has not grown for this long is a leftover (crashed or paused browser), not a download.
    private static let staleAfter: TimeInterval = 10 * 60
    private var tracked: [String: Tracked] = [:]
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

    func start() {
        guard source == nil else { return }
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        s.setEventHandler { MainActor.assumeIsolated { DownloadsProvider.shared.scan() } }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
        scan()
    }

    func stop() {
        source?.cancel(); source = nil
        timer?.invalidate(); timer = nil
        for path in tracked.keys { AppModel.shared.center.remove("download-\(path)", now: Date()) }
        tracked = [:]
        AppModel.shared.downloadFinished()
    }

    private func scan() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for n in names {
            let path = dir.appendingPathComponent(n).path
            guard tracked[path] == nil, let p = DownloadWatcher.classify(path),
                  Date().timeIntervalSince(Self.modified(path)) < Self.staleAfter else { continue }
            tracked[path] = Tracked(partial: p, bytes: 0, changedAt: Date())
        }
        tick()
        if !tracked.isEmpty && timer == nil {
            let t = Timer(timeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { DownloadsProvider.shared.tick() } }
            t.tolerance = 0.3
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func tick() {
        let fm = FileManager.default
        let m = AppModel.shared
        let now = Date()
        for (path, var t) in tracked {
            let id = "download-\(path)"
            if let final = DownloadWatcher.finishedPath(t.partial, exists: fm.fileExists(atPath:)) {
                tracked[path] = nil
                m.center.remove(id, now: now)
                m.center.post(Activity(id: "download-done-\(final)", kind: .notify, priority: .p1, state: .success, symbol: "arrow.down.circle",
                                       label: L("downloads.done"), value: "", detail: L("downloads.finished", (final as NSString).lastPathComponent),
                                       genericDetail: L("downloads.generic"), url: "dl:\(final)", startedAt: now), now: now)
                m.downloadFinished()
                continue
            }
            let bytes = Self.size(path)
            if bytes != t.bytes { t.bytes = bytes; t.changedAt = now }
            // Cancelled, or stuck long enough to be a leftover.
            guard fm.fileExists(atPath: path), now.timeIntervalSince(t.changedAt) < Self.staleAfter else {
                tracked[path] = nil; m.center.remove(id, now: now); m.downloadFinished(); continue
            }
            var progress: Double?
            if t.partial.browser == .safari, let d = fm.contents(atPath: (path as NSString).appendingPathComponent("Info.plist")) {
                progress = DownloadWatcher.safariProgress(infoPlist: d)
            }
            tracked[path] = t
            let value = progress.map { "\(Int($0 * 100))%" } ?? ByteCountFormatter.string(fromByteCount: t.bytes, countStyle: .file)
            let a = Activity(id: id, kind: .script, priority: .p2, state: .running, symbol: "arrow.down.circle",
                             label: TextRules.truncateMiddle(t.partial.finalName, max: 12), value: value,
                             detail: L("downloads.progress", t.partial.finalName, value), genericDetail: L("downloads.generic"),
                             progress: progress, startedAt: m.center.activities[id]?.startedAt ?? now,
                             updatedAt: m.center.activities[id]?.updatedAt ?? now)
            if m.center.activities[id] != a { m.center.upsert(a) }
        }
        if tracked.isEmpty { timer?.invalidate(); timer = nil }
        m.scheduleTick()
    }

    var active: Bool { !tracked.isEmpty }

    /// Newest modification date of the file, or of anything inside a Safari `.download` bundle.
    private static func modified(_ path: String) -> Date {
        let fm = FileManager.default
        let own = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
        let inner = (try? fm.contentsOfDirectory(atPath: path))?.compactMap {
            try? fm.attributesOfItem(atPath: (path as NSString).appendingPathComponent($0))[.modificationDate] as? Date
        }.max()
        return max(own, inner ?? .distantPast)
    }

    private static func size(_ path: String) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return (try? fm.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0 }
        return (fm.enumerator(atPath: path)?.compactMap { try? fm.attributesOfItem(atPath: (path as NSString).appendingPathComponent($0 as! String))[.size] as? Int64 }.reduce(0, +)) ?? 0
    }
}
