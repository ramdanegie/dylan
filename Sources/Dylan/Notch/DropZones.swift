import AppKit
import DylanCore
import SwiftUI

/// Drop actions (FR-109, design D56). A file dragged near the top edge opens the island as a set of zones:
/// Shelf and Compress always, AirDrop, iCloud Drive and Share when available, plus cloud folders that are
/// installed (OneDrive, Google Drive, Dropbox…). Images also get Remove background and Resize.
enum DropZone: Hashable, Identifiable {
    case shelf, compress, airdrop, share, removeBackground, resize
    case folder(name: String, path: String)

    var id: String {
        switch self {
        case .folder(_, let p): return p
        default: return "\(self)"
        }
    }

    var symbol: String {
        switch self {
        case .shelf: return "tray.and.arrow.down"
        case .compress: return "doc.zipper"
        case .airdrop: return "airplayaudio"
        case .share: return "square.and.arrow.up"
        case .removeBackground: return "person.crop.rectangle"
        case .resize: return "arrow.down.right.and.arrow.up.left"
        case .folder(let n, _): return n == "iCloud Drive" ? "icloud.and.arrow.up" : "externaldrive.badge.icloud"
        }
    }

    var title: String {
        switch self {
        case .folder(let n, _): return n
        default: return L("drop.\(id)")
        }
    }

    var hint: String {
        switch self {
        case .folder: return L("drop.folderHint")
        default: return L("drop.\(id).hint")
        }
    }

    /// iCloud Drive and the File Provider folders in ~/Library/CloudStorage.
    static var cloudFolders: [DropZone] {
        let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
        var out: [DropZone] = []
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if fm.fileExists(atPath: icloud.path) { out.append(.folder(name: "iCloud Drive", path: icloud.path)) }
        let storage = home.appendingPathComponent("Library/CloudStorage")
        for name in ((try? fm.contentsOfDirectory(atPath: storage.path)) ?? []).sorted() where !name.hasPrefix(".") {
            // "GoogleDrive-me@example.com" → "Google Drive"; the account is not shown.
            let service = name.split(separator: "-").first.map(String.init) ?? name
            let pretty = ["GoogleDrive": "Google Drive", "OneDrive": "OneDrive", "Dropbox": "Dropbox", "Box": "Box"][service] ?? service
            out.append(.folder(name: pretty, path: storage.appendingPathComponent(name).path))
        }
        return out
    }

    static func zones(imagesOnly: Bool) -> [DropZone] {
        var z: [DropZone] = [.shelf, .compress]
        if NSSharingService(named: .sendViaAirDrop) != nil { z.append(.airdrop) }
        z += cloudFolders.prefix(2)
        z.append(.share)
        if imagesOnly { z += [.removeBackground, .resize] }
        return z
    }
}

struct DropZonesView: View {
    private var model: AppModel { AppModel.shared }
    @StateBox private var targeted: DropZone?
    /// Read once when the zones open (it lists the cloud folders), not on every redraw.
    @StateBox private var zones = DropZone.zones(imagesOnly: DropActions.dragIsImages())

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SwiftUI.Text(L("drop.title")).font(DY.font(13, .semibold)).foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: min(4, zones.count)), spacing: 8) {
                ForEach(zones) { z in zone(z) }
            }
        }
    }

    private func zone(_ z: DropZone) -> some View {
        let on = targeted == z
        return VStack(spacing: 4) {
            Image(systemName: z.symbol).font(.system(size: 17, weight: .medium))
            SwiftUI.Text(z.title).font(DY.font(12, .semibold)).lineLimit(1)
            SwiftUI.Text(z.hint).font(DY.font(10, .regular)).foregroundStyle(on ? Color.black.opacity(0.6) : DY.fg2).lineLimit(1)
        }
        .foregroundStyle(on ? .black : .white)
        .frame(maxWidth: .infinity, minHeight: 68)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Color.white : Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(on ? 0 : 0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .animation(.easeOut(duration: 0.12), value: on)
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { targeted == z }, set: { targeted = $0 ? z : (targeted == z ? nil : targeted) })) { providers in
            DropActions.load(providers) { DropActions.run(z, $0) }
            return true
        }
        .accessibilityElement(children: .combine)
    }
}

enum DropActions {
    /// Whether every file on the drag pasteboard is an image (images get extra zones).
    static func dragIsImages() -> Bool {
        let urls = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return !urls.isEmpty && urls.allSatisfy { VisionTools.isImage($0.path) }
    }

    static func load(_ providers: [NSItemProvider], then: @escaping @MainActor ([URL]) -> Void) {
        let box = URLBox()
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { @Sendable url, _ in
                if let url { box.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { MainActor.assumeIsolated { AppModel.shared.dropping = false; then(box.urls) } }
    }

    static func run(_ zone: DropZone, _ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let m = AppModel.shared
        switch zone {
        case .shelf:
            ShelfProvider.shared.add(urls)
            m.selectedTab = .shelf
            m.notchState = .expanded
        case .compress:
            Task.detached {
                let out = Self.zip(urls)
                await MainActor.run { out.map { done("drop.compressed", $0) } ?? failed() }
            }
        case .airdrop:
            m.notchState = .closed
            NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
        case .share:
            NotchController.shared.share(urls)
        case .folder(let name, let path):
            Task.detached {
                var last: URL?
                for u in urls {
                    let dest = URL(fileURLWithPath: Shelf.freePath(dir: path, name: u.lastPathComponent))
                    if (try? FileManager.default.copyItem(at: u, to: dest)) != nil { last = dest }
                }
                await MainActor.run { last.map { done("drop.copied", $0, name) } ?? failed() }
            }
        case .removeBackground:
            Task {
                var last: URL?
                for u in urls { last = await VisionTools.removeBackground(u) ?? last }
                last.map { done("drop.cutout", $0) } ?? failed()
            }
        case .resize:
            Task {
                var last: URL?
                for u in urls { last = await FileTransforms.convert(u, to: .png, scale: 0.5) ?? last }
                last.map { done("drop.resized", $0) } ?? failed()
            }
        }
    }

    /// One file or folder → name.zip next to it; several → Archive.zip next to the first.
    nonisolated static func zip(_ urls: [URL]) -> URL? {
        let dir = urls[0].deletingLastPathComponent().path
        let name = urls.count == 1 ? urls[0].lastPathComponent + ".zip" : "Archive.zip"
        let out = URL(fileURLWithPath: Shelf.freePath(dir: dir, name: name))
        let ok: Bool
        if urls.count == 1 {
            ok = Shell.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", urls[0].path, out.path],
                           timeout: 600, requireSuccess: true) != nil
        } else {
            // Same folder: store plain names; otherwise zip keeps each path (minus the leading slash).
            let same = urls.allSatisfy { $0.deletingLastPathComponent().path == dir }
            // "./name": a file called "-m…" must not be read as an option (zip -m deletes the originals).
            ok = Shell.run("/usr/bin/zip", ["-r", "-q", "-y", out.path] + urls.map { same ? "./" + $0.lastPathComponent : $0.path },
                           timeout: 600, cwd: same ? dir : nil, requireSuccess: true) != nil
        }
        guard ok, FileManager.default.fileExists(atPath: out.path) else {
            try? FileManager.default.removeItem(at: out)   // a half-written archive is not left next to the user's files
            return nil
        }
        return out
    }

    @MainActor private static func done(_ key: String, _ url: URL, _ arg: String = "") {
        let now = Date(), m = AppModel.shared
        m.center.post(Activity(id: "drop-\(now.timeIntervalSince1970)", kind: .notify, priority: .p1, state: .success, symbol: "checkmark",
                               label: L("drop.done"), detail: L(key, url.lastPathComponent, arg), url: "dl:" + url.path, startedAt: now), now: now)
        m.scheduleTick()
    }

    @MainActor private static func failed() {
        let now = Date(), m = AppModel.shared
        m.center.post(Activity(id: "drop-failed", kind: .notify, priority: .p1, state: .failure, symbol: "xmark",
                               label: L("compact.error"), detail: L("drop.failed"), startedAt: now), now: now)
        m.scheduleTick()
    }
}

/// Collects URLs from item-provider callbacks (any thread).
private nonisolated final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [URL] = []
    func append(_ u: URL) { lock.lock(); list.append(u); lock.unlock() }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return list }
}
