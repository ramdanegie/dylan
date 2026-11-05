import AppKit
import DylanCore

/// Focus on/off (FR-72, design D32): a short P3 activity when Focus changes. Watches the DoNotDisturb
/// store directory; no polling. If macOS blocks reading it, the feature stays silent (hint in Settings).
@Observable
final class FocusProvider {
    static let shared = FocusProvider()
    private var source: DispatchSourceFileSystemObject?
    private var current: String?
    /// The Focus that is on now, nil when none.
    private(set) var mode: FocusMode.Mode?
    private var pending: DispatchWorkItem?
    /// macOS refused the DoNotDisturb folder (it needs Full Disk Access on macOS 27); Settings says so.
    private(set) var blocked = false
    private static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")

    func start() {
        guard source == nil else { return }
        let fd = open(Self.dir.path, O_EVTONLY)
        blocked = fd < 0
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        s.setEventHandler { MainActor.assumeIsolated { FocusProvider.shared.changed() } }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
        mode = Self.read()
        current = mode?.id   // the state at launch is not news
    }

    func stop() {
        source?.cancel(); source = nil
        if mode != nil { mode = nil; current = nil; NotificationLog.shared.focusEnded() }
        pending?.cancel(); pending = nil
    }

    /// The store is rewritten in a few steps; read once it settles.
    private func changed() {
        pending?.cancel()
        let w = DispatchWorkItem { MainActor.assumeIsolated { FocusProvider.shared.check() } }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    private func check() {
        let mode = Self.read()
        guard mode?.id != current else { return }
        current = mode?.id
        self.mode = mode
        if mode == nil { NotificationLog.shared.focusEnded() } else { NotificationLog.shared.refreshHeld() }
        let m = AppModel.shared
        guard m.features.isEnabled(.focus) else { return }
        let now = Date()
        m.center.post(Activity(id: "focus", kind: .focus, priority: .p3, state: .info,
                               symbol: mode.map { $0.symbol ?? "moon.fill" } ?? "moon",
                               label: mode == nil ? L("focus.off") : L("focus.on"),
                               detail: mode.map { $0.name.map { L("focus.onNamed", $0) } ?? L("focus.on") } ?? L("focus.off"),
                               startedAt: now), now: now)
        m.scheduleTick()
    }

    private static func read() -> FocusMode.Mode? {
        guard let a = try? Data(contentsOf: dir.appendingPathComponent("Assertions.json")) else { return nil }
        return FocusMode.active(assertions: a, modes: try? Data(contentsOf: dir.appendingPathComponent("ModeConfigurations.json")))
    }
}
