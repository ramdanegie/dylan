import AppKit
import AVFoundation
import DylanCore
import ScreenCaptureKit

/// Recording preferences (Settings → Screenshot → Screen recording).
enum RecordPrefs {
    static var d: UserDefaults { AppModel.store }
    static var systemAudio: Bool { d.object(forKey: "rec.systemAudio") as? Bool ?? true }
    static var microphone: Bool { d.bool(forKey: "rec.mic") }
    static var showClicks: Bool { d.object(forKey: "rec.clicks") as? Bool ?? true }
    static var fps: Int { d.object(forKey: "rec.fps") as? Int ?? 60 }
}

/// Screen recording (FR-94): the whole screen or a dragged area to an MP4 in the capture folder, through
/// ScreenCaptureKit's recording output (macOS 15). Dylan's own windows stay out of the video. While it runs the
/// notch shows a red dot and the time; Stop in the notch, the menu or ⌥⇧5 again ends it, and the file is announced
/// like a saved screenshot ("click to open in Finder").
@Observable
final class ScreenRecorder {
    static let shared = ScreenRecorder()
    private(set) var isRecording = false

    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var output: SCRecordingOutput?
    @ObservationIgnored private var file: URL?
    @ObservationIgnored private var border: NSPanel?
    @ObservationIgnored private var starting = false
    @ObservationIgnored private var onFinish: [() -> Void] = []
    @ObservationIgnored private let delegate = RecordingDelegate()

    /// Starting, recording, or still writing the last file: no second recording, and quitting waits.
    var isBusy: Bool { starting || stream != nil || file != nil }
    @ObservationIgnored private var stopRequested = false

    /// ⌥⇧5 and the menu: choose what to record, or stop.
    func toggle() {
        if isRecording { stop() } else if isBusy { busy() } else { CaptureOverlay.shared.start(.record) }
    }

    /// `region` in global AppKit points; nil records the whole screen.
    func start(region: CGRect?, screen: NSScreen) {
        guard !isBusy else { return busy() }
        starting = true
        Task {
            await begin(region: region, screen: screen)
            starting = false
            if stream == nil && file == nil { runFinish() }   // it never started: let a waiting quit go on
            else if stopRequested { stop() }
            stopRequested = false
        }
    }

    private func begin(region: CGRect?, screen: NSScreen) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == id }) else { return failed(nil) }
        let me = getpid()
        // The whole app, so windows Dylan opens during the recording (Settings, the editor) stay out of it too.
        let filter = SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.processID == me }, exceptingWindows: [])
        let config = SCStreamConfiguration()
        if let region { config.sourceRect = ScreenRecording.sourceRect(region, screen: screen.frame) }
        let px = ScreenRecording.pixelSize(points: region?.size ?? screen.frame.size, scale: screen.backingScaleFactor)
        config.width = px.width
        config.height = px.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(RecordPrefs.fps))
        config.showsCursor = true
        config.showMouseClicks = RecordPrefs.showClicks
        config.capturesAudio = RecordPrefs.systemAudio
        config.excludesCurrentProcessAudio = true
        // The microphone only when asked for and allowed; a refusal still records, just without it.
        config.captureMicrophone = RecordPrefs.microphone ? await AVCaptureDevice.requestAccess(for: .audio) : false

        let dir = ShotPrefs.folder
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // A free name, not reserved with an empty file: the writer refuses to start on an existing file.
        let url = URL(fileURLWithPath: Shelf.freePath(dir: dir.path, name: CaptureStore.fileName(Date(), ext: "mp4")))
        let oc = SCRecordingOutputConfiguration()
        oc.outputURL = url
        oc.outputFileType = .mp4
        oc.videoCodecType = .h264
        let out = SCRecordingOutput(configuration: oc, delegate: delegate)
        let s = SCStream(filter: filter, configuration: config, delegate: delegate)
        // Known before capture starts, so a failure reported while starting is matched to this recording.
        file = url; output = out
        do {
            try s.addRecordingOutput(out)
            try await s.startCapture()
        } catch {
            if file == url { file = nil; output = nil; Self.removeIfEmpty(url) }
            return failed(error.localizedDescription)
        }
        // The output already failed while starting (finish ran): do not leave the stream running.
        guard file == url else { Task { try? await s.stopCapture() }; return }
        stream = s
        isRecording = true
        if let region { showBorder(region) }
        AppModel.shared.center.upsert(Activity(id: "recording", kind: .capture, priority: .p1, state: .running, symbol: "record.circle",
                                               label: L("rec.recording"), detail: L("rec.stopHint"), startedAt: Date()))
        AppModel.shared.scheduleTick()
    }

    /// Ends the recording; `then` runs once the file is complete (used when Dylan quits mid-recording).
    func stop(then: (() -> Void)? = nil) {
        if let then { onFinish.append(then) }
        guard let s = stream else {
            if starting { stopRequested = true } else if file == nil { runFinish() }   // else: the file is still being written
            return
        }
        stream = nil
        ended()
        Task { try? await s.stopCapture() }
        finishLater(nil)
    }

    /// The stream stopped by itself (display gone, permission taken away): keep what was recorded.
    fileprivate func streamStopped(_ id: ObjectIdentifier, _ message: String) {
        guard let s = stream, ObjectIdentifier(s) == id else { return }
        stream = nil
        ended()
        finishLater(message)
    }

    /// The output reports when the file is complete; this is the fallback if it never does, timed on its own so a
    /// stuck `stopCapture` cannot keep a quit waiting forever.
    private func finishLater(_ message: String?) {
        let url = file
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            MainActor.assumeIsolated { if ScreenRecorder.shared.file == url { ScreenRecorder.shared.finish(message, from: nil) } }
        }
    }

    private func ended() {
        isRecording = false
        hideBorder()
        AppModel.shared.removeIfPresent("recording", now: Date())
    }

    /// The file is done (or failed): announce it, or say why there is none. `from` is the output that reported it;
    /// a late report from an earlier recording is ignored.
    fileprivate func finish(_ message: String?, from id: ObjectIdentifier?) {
        guard let url = file else { return }
        if let id, output.map(ObjectIdentifier.init) != id { return }
        file = nil; output = nil
        // The writer failed mid-recording (disk full…): stop capturing too.
        if let s = stream {
            stream = nil
            ended()
            Task { try? await s.stopCapture() }
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size > 0 { ScreenshotService.shared.announceSaved(url) } else { Self.removeIfEmpty(url) }
        // Saved but cut short, or nothing at all: say why.
        if let message { failed(message) } else if size == 0 { failed(nil) }
        runFinish()
    }

    private static func removeIfEmpty(_ url: URL) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size == 0 { try? FileManager.default.removeItem(at: url) }
    }

    private func runFinish() {
        let callbacks = onFinish
        onFinish = []
        callbacks.forEach { $0() }
    }

    private func busy() {
        let now = Date()
        AppModel.shared.center.post(Activity(id: "recording-busy", kind: .capture, priority: .p2, state: .info, symbol: "hourglass",
                                             label: L("rec.recording"), detail: L("rec.busy"), startedAt: now), now: now)
        AppModel.shared.scheduleTick()
    }

    private func failed(_ message: String?) {
        let now = Date()
        AppModel.shared.center.post(Activity(id: "recording-failed", kind: .capture, priority: .p2, state: .failure, symbol: "exclamationmark.triangle",
                                             label: L("rec.failed"), detail: message ?? L("rec.failedDetail"), startedAt: now), now: now)
        AppModel.shared.scheduleTick()
    }

    // MARK: A click-through frame around a recorded area (never in the video: Dylan's windows are excluded)

    private func showBorder(_ region: CGRect) {
        let b = NSPanel(contentRect: region.insetBy(dx: -3, dy: -3), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        b.isOpaque = false; b.backgroundColor = .clear; b.ignoresMouseEvents = true; b.level = .screenSaver; b.sharingType = .none
        b.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let v = NSView(frame: CGRect(origin: .zero, size: b.frame.size))
        v.wantsLayer = true
        v.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.85).cgColor
        v.layer?.borderWidth = 2
        v.layer?.cornerRadius = 4
        b.contentView = v
        b.orderFrontRegardless()
        border = b
    }

    private func hideBorder() {
        border?.orderOut(nil)
        border = nil
    }
}

/// ScreenCaptureKit calls back on its own queues; everything is handed to the main actor with the identity of the
/// stream or output it came from.
private final class RecordingDelegate: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let message = error.localizedDescription, id = ObjectIdentifier(stream)
        Task { @MainActor in ScreenRecorder.shared.streamStopped(id, message) }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let id = ObjectIdentifier(recordingOutput)
        Task { @MainActor in ScreenRecorder.shared.finish(nil, from: id) }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let message = error.localizedDescription, id = ObjectIdentifier(recordingOutput)
        Task { @MainActor in ScreenRecorder.shared.finish(message, from: id) }
    }
}
