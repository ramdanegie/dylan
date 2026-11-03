import AppKit
import CoreAudio
import DylanCore

/// A view that can show real levels (the equalizer's layers).
@MainActor protocol LevelView: AnyObject {
    func show(levels: [Float])
    func stopLevels()
}

/// Real equalizer from the playing media app (FR-63). Opt-in: macOS asks for audio-capture permission.
/// Without permission the tap delivers silence; after 3 s of silence while playing, the bars go back to
/// the decorative animation.
final class VisualizerProvider {
    static let shared = VisualizerProvider()
    private var tap: AudioTap?
    private var views = NSHashTable<AnyObject>.weakObjects()
    private var lastSound = Date.distantPast
    private(set) var live = false

    func register(_ v: LevelView) { views.add(v) }

    /// Media changed, or the feature was toggled.
    func update() {
        let m = AppModel.shared
        guard m.features.isEnabled(.visualizer), let media = m.media, media.isPlaying,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: media.source == .spotify ? "com.spotify.client" : "com.apple.Music").first
        else { stop(); return }
        guard tap?.pid != app.processIdentifier else { return }
        stop()
        let spectrum = SpectrumBox()
        lastSound = Date()
        tap = AudioTap(pid: app.processIdentifier, processes: AudioTap.processObjects(of: app.processIdentifier), mode: .observe) { samples, rate in
            guard let levels = spectrum.feed(samples, rate) else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { VisualizerProvider.shared.push(levels) } }
        }
    }

    func stop() {
        tap?.destroy(); tap = nil
        if live { live = false; for case let v as LevelView in views.allObjects { v.stopLevels() } }
    }

    private func push(_ levels: [Float]) {
        guard tap != nil else { return }
        let now = Date()
        if levels.contains(where: { $0 > 0.02 }) { lastSound = now }
        // Silence for 3 s while "playing": no permission, or a quiet passage; show the animation instead.
        let audible = now.timeIntervalSince(lastSound) < 3
        if audible != live {
            live = audible
            if !audible { for case let v as LevelView in views.allObjects { v.stopLevels() } }
        }
        guard audible else { return }
        for case let v as LevelView in views.allObjects { v.show(levels: levels) }
    }
}

/// Spectrum is used on the audio queue only; this box makes it capturable there. ~30 updates a second.
nonisolated final class SpectrumBox: @unchecked Sendable {
    private let spectrum = Spectrum()
    private var lastSent: CFTimeInterval = 0
    func feed(_ s: UnsafeBufferPointer<Float>, _ rate: Double) -> [Float]? {
        guard let l = spectrum.feed(s, sampleRate: rate) else { return nil }
        let now = CACurrentMediaTime()
        guard now - lastSent >= 1.0 / 30 else { return nil }
        lastSent = now
        return l
    }
}

/// Volume per app (FR-84): an app below 100% is muted at the source and played back by Dylan × gain.
/// At 100% the tap is removed, so untouched apps never go through Dylan. Not persisted.
@Observable
final class AppVolumeProvider {
    static let shared = AppVolumeProvider()

    struct App: Identifiable, Equatable {
        var id: pid_t
        var name: String
        var icon: NSImage?
    }

    var apps: [App] = []
    var volumes: [pid_t: Float] = [:]
    @ObservationIgnored private var taps: [pid_t: AudioTap] = [:] { didSet { watchOutput(!taps.isEmpty) } }
    @ObservationIgnored private var outputListener: AudioObjectPropertyListenerBlock?
    private static var defaultOutput = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                                  mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    /// Only while an app is turned down: the taps are clocked by the output they were built on.
    private func watchOutput(_ on: Bool) {
        if on, outputListener == nil {
            let b: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { AppVolumeProvider.shared.outputChanged() } }
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutput, .main, b)
            outputListener = b
        } else if !on, let b = outputListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutput, .main, b)
            outputListener = nil
        }
    }

    func refresh() {
        taps = taps.filter { NSRunningApplication(processIdentifier: $0.key) != nil }
        var list: [App] = []
        for p in AudioTap.processes() where p.playing && !list.contains(where: { $0.id == p.app.processIdentifier }) {
            list.append(App(id: p.app.processIdentifier, name: p.app.localizedName ?? "", icon: p.app.icon))
        }
        // A muted-at-source app may not report output; keep the ones Dylan is controlling.
        for pid in taps.keys where !list.contains(where: { $0.id == pid }) {
            if let a = NSRunningApplication(processIdentifier: pid) { list.append(App(id: pid, name: a.localizedName ?? "", icon: a.icon)) }
        }
        apps = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func volume(_ pid: pid_t) -> Float { volumes[pid] ?? 1 }

    func set(_ pid: pid_t, _ v: Float) {
        let v = min(1, max(0, v))
        volumes[pid] = v
        if v >= 0.995 { taps[pid]?.destroy(); taps[pid] = nil; volumes[pid] = nil; return }
        if let t = taps[pid] { t.gain.value = v; return }
        guard let t = AudioTap(pid: pid, processes: AudioTap.processObjects(of: pid), mode: .gain) else { volumes[pid] = nil; return }
        t.gain.value = v
        taps[pid] = t
    }

    /// The default output changed: the taps play through the old device, so rebuild them.
    func outputChanged() {
        let current = taps.mapValues { $0.gain.value }
        taps.values.forEach { $0.destroy() }
        taps = [:]
        for (pid, v) in current { set(pid, v) }
    }

    func stopAll() {
        taps.values.forEach { $0.destroy() }
        taps = [:]; volumes = [:]
    }
}
