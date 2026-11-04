import AppKit
import AVFoundation
import CryptoKit
import DylanCore
import OpenDirectory
import Vision

/// Face Unlock (PRD §F15, FR-50–55): experimental, off by default, never on without an enrollment the user
/// started. See docs/face-unlock.md for the threat model. In short: built-in camera only, a random spoken
/// challenge (look left, blink…) with identity checked on every frame, Apple-style limits (5 failures, 48 h,
/// never after a restart, one password per lock), the password verified before it is stored, and a local
/// audit log without images.
@Observable
final class FaceUnlockProvider {
    static let shared = FaceUnlockProvider()

    var vault = FaceVault()
    var status: String?
    var busy = false
    @ObservationIgnored private var lockedAt: Date?
    @ObservationIgnored private var lockManual = false
    @ObservationIgnored private var typedThisLock = false
    @ObservationIgnored private var deniedLoggedThisLock = false
    /// Persisted in the vault: restarting Dylan must not force another password unlock (restarting the Mac still does).
    private var lastPasswordUnlock: Date? {
        get { vault.lastPasswordUnlock }
        set { vault.lastPasswordUnlock = newValue }
    }
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var camera: FaceCamera?

    private static var vaultURL: URL { Bridge.socketURL.deletingLastPathComponent().appendingPathComponent("face.sealed") }

    var enrolled: Bool { vault.template != nil && Keychain.exists("faceunlock.password") }
    var enabled: Bool { vault.settings.enabled && enrolled }

    // MARK: Lifecycle

    func start() {
        load()
        guard observers.isEmpty else { return }
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { FaceUnlockProvider.shared.didLock() }
        })
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { FaceUnlockProvider.shared.didUnlock() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { FaceUnlockProvider.shared.screenWoke() }
        })
    }

    private func didLock() {
        lockedAt = Date()
        // Locked by the user right now (⌃⌘Q, menu) rather than by idle: do not open again at once.
        lockManual = [CGEventType.keyDown, .leftMouseDown, .mouseMoved]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? .infinity < 2
        typedThisLock = false
        deniedLoggedThisLock = false
    }

    private func didUnlock() {
        guard vault.template != nil else { lockedAt = nil; return }   // never enrolled: nothing to record
        let now = Date()
        unlockCheck?.cancel(); unlockCheck = nil
        if typedThisLock {
            let failed = vault.log.failuresSinceLastUnlock
            record(.init(at: now, result: .unlocked))
            vault.consecutiveFailures = 0
            AppModel.shared.center.post(Activity(id: "faceunlock", kind: .notify, priority: .p1, state: .success, symbol: "faceid",
                                                 label: L("faceUnlock.short"), detail: L("faceUnlock.unlocked", failed), startedAt: now), now: now)
            AppModel.shared.scheduleTick()
        } else {
            // A manual unlock (password or Touch ID — macOS does not say which) resets the failures.
            lastPasswordUnlock = now
            vault.consecutiveFailures = 0
        }
        lockedAt = nil
        typedThisLock = false
        save()
    }

    private func screenWoke() {
        guard enabled, Self.screenLocked else { return }
        attempt()
    }

    func disable() {
        vault.settings.enabled = false
        save()
        camera?.stop(); camera = nil
    }

    // MARK: One attempt (≤ 6 s of camera)

    private var facts: FaceUnlockPolicy.Facts {
        FaceUnlockPolicy.Facts(now: Date(), screenLocked: Self.screenLocked, lockedAt: lockedAt, lockWasManual: lockManual,
                               bootTime: Self.bootTime, lastPasswordUnlock: lastPasswordUnlock, consecutiveFailures: vault.consecutiveFailures,
                               passwordTypedThisLock: typedThisLock, enrolled: enrolled, accessibilityTrusted: AXIsProcessTrusted(),
                               presentationMode: AppModel.shared.presentationMode, network: nil)
    }

    // State of the running attempt or enrollment (main actor). Frames arrive on the camera queue and hop here.
    @ObservationIgnored private var challenge: LivenessChallenge?
    @ObservationIgnored private var tracker = FaceGeometry.Tracker()
    @ObservationIgnored private var bestIdentity: Double = 0
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var enrollPrints: [[Float]] = []
    @ObservationIgnored private var watchdog: DispatchWorkItem?
    @ObservationIgnored private var unlockCheck: DispatchWorkItem?

    private func attempt() {
        guard camera == nil, vault.template != nil else { return }
        if let d = FaceUnlockPolicy(settings: vault.settings).denial(facts) {
            if !deniedLoggedThisLock { deniedLoggedThisLock = true; record(.init(at: Date(), result: .denied, reason: d.rawValue)) }
            return
        }
        var g = SystemRandomNumberGenerator()
        let c = LivenessChallenge.random(using: &g)
        challenge = c
        tracker = FaceGeometry.Tracker()
        bestIdentity = 0
        startedAt = Date()
        Speech.say(c.steps.map { L("faceUnlock.step.\($0.rawValue)") }.joined(separator: ", "))
        camera = FaceCamera { frame in
            DispatchQueue.main.async { MainActor.assumeIsolated { FaceUnlockProvider.shared.attemptFrame(frame) } }
        }
        guard camera != nil else { challenge = nil; record(.init(at: Date(), result: .failed, reason: "noCamera", steps: c.steps)); return }
        // No frames at all (camera busy or blocked) must not leave the attempt open forever.
        arm(after: LivenessChallenge.window + 2) { p in
            guard let c = p.challenge else { return }
            p.finish(passed: false, reason: LivenessChallenge.Reason.timeout.rawValue, identity: p.bestIdentity, steps: c.steps)
        }
    }

    private func attemptFrame(_ frame: FaceCamera.Frame) {
        guard camera != nil, var c = challenge, let template = vault.template else { return }
        let identity = frame.print.map { FaceMatcher.identity($0, template) } ?? 0
        bestIdentity = max(bestIdentity, identity)
        let sample = LivenessChallenge.Sample(time: Date().timeIntervalSince(startedAt), faceCount: frame.faceCount,
                                              trackID: frame.box.map { tracker.track($0) }, yaw: frame.yaw, pitch: frame.pitch,
                                              eyesOpen: frame.eyesOpen, identity: identity)
        let outcome = c.feed(sample)
        challenge = c
        switch outcome {
        case .inProgress: return
        case .passed: finish(passed: true, reason: nil, identity: bestIdentity, steps: c.steps)
        case .failed(let r): finish(passed: false, reason: r.rawValue, identity: bestIdentity, steps: c.steps)
        }
    }

    private func arm(after seconds: TimeInterval, _ f: @escaping @MainActor (FaceUnlockProvider) -> Void) {
        watchdog?.cancel()
        let w = DispatchWorkItem { MainActor.assumeIsolated { f(FaceUnlockProvider.shared) } }
        watchdog = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    private func finish(passed: Bool, reason: String?, identity: Double, steps: [LivenessChallenge.Step]) {
        watchdog?.cancel(); watchdog = nil
        camera?.stop(); camera = nil
        challenge = nil
        guard passed else {
            vault.consecutiveFailures += 1
            record(.init(at: Date(), result: .failed, reason: reason, identity: identity, steps: steps))
            return
        }
        // Re-check right before typing: unlocked meanwhile, or the policy changed (e.g. Presentation Mode).
        guard Self.screenLocked, FaceUnlockPolicy(settings: vault.settings).denial(facts) == nil,
              let password = Keychain.get("faceunlock.password") else { return }
        typedThisLock = true
        save()
        Self.type(password)
        // Still locked a few seconds later: the stored password is wrong (changed since enrollment). Stop typing it.
        unlockCheck?.cancel()
        let w = DispatchWorkItem { MainActor.assumeIsolated {
            let p = FaceUnlockProvider.shared
            guard Self.screenLocked, p.typedThisLock else { return }
            p.record(.init(at: Date(), result: .failed, reason: "passwordRejected", identity: identity, steps: steps))
            p.disable()
        } }
        unlockCheck = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
    }

    private func record(_ e: FaceUnlockEvent) { vault.log.append(e); save() }

    // MARK: Enrollment (FR-50, design D19: risks → camera → password → ready)

    /// Frames kept for the template (design: "20/20 frame").
    static let enrollTarget = 20
    enum EnrollState: Equatable { case idle, capturing, captured, failed(String) }
    var enrollState: EnrollState = .idle
    var enrollCount = 0
    /// Faces in the latest frame, so the wizard can say "only one face".
    var enrollFaces = 0
    /// The running camera, for the wizard's live preview (never stored).
    private(set) var enrollCamera: FaceCamera?
    @ObservationIgnored private var lastEnrollFrame = Date.distantPast

    /// Step 2: the camera runs with a preview while the user turns their head; one print every 0.25 s.
    func beginEnrollCapture() {
        cancelEnroll()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { @Sendable granted in
                Task { @MainActor in
                    if granted { FaceUnlockProvider.shared.beginEnrollCapture() }
                    else { FaceUnlockProvider.shared.enrollState = .failed(L("faceUnlock.noCamera")) }
                }
            }
            return
        default: enrollState = .failed(L("faceUnlock.noCamera")); return
        }
        enrollPrints = []
        enrollCount = 0
        enrollState = .capturing
        enrollCamera = FaceCamera(duration: 30) { frame in
            DispatchQueue.main.async { MainActor.assumeIsolated { FaceUnlockProvider.shared.enrollFrame(frame) } }
        }
        guard enrollCamera != nil else { enrollState = .failed(L("faceUnlock.noCamera")); return }
        arm(after: 30) { $0.endEnrollCapture() }
    }

    private func enrollFrame(_ frame: FaceCamera.Frame) {
        guard enrollState == .capturing else { return }
        enrollFaces = frame.faceCount
        guard frame.faceCount == 1, let f = frame.print, Date().timeIntervalSince(lastEnrollFrame) >= 0.25 else { return }
        lastEnrollFrame = Date()
        enrollPrints.append(f)
        enrollCount = enrollPrints.count
        if enrollCount >= Self.enrollTarget { endEnrollCapture() }
    }

    private func endEnrollCapture() {
        guard enrollState == .capturing else { return }
        watchdog?.cancel(); watchdog = nil
        enrollCamera?.stop(); enrollCamera = nil
        enrollState = enrollPrints.count >= FaceMatcher.minimumFrames ? .captured : .failed(L("faceUnlock.enrollFailed"))
    }

    /// Batal / closing the wizard: camera off, nothing kept.
    func cancelEnroll() {
        if enrollState == .capturing { watchdog?.cancel(); watchdog = nil }
        enrollCamera?.stop(); enrollCamera = nil
        enrollPrints = []
        enrollCount = 0
        enrollState = .idle
    }

    /// Step 3: the password is verified before anything is stored; then the template is sealed and the feature is on.
    func completeEnrollment(password: String) -> String? {
        guard enrollState == .captured else { return L("faceUnlock.enrollFailed") }
        guard Self.verify(password: password) else { return L("faceUnlock.wrongPassword") }
        guard let t = FaceMatcher.enroll(enrollPrints, now: Date()) else { return L("faceUnlock.enrollFailed") }
        Keychain.set(password, "faceunlock.password")
        vault.template = t
        vault.settings.enabled = true
        lastPasswordUnlock = Date()   // the login password was just verified, in this boot
        save()
        status = L("faceUnlock.enrolled", enrollPrints.count)
        enrollPrints = []
        enrollState = .idle
        return nil
    }

    /// "Coba kunci sekarang" (D19 step 4): lock like ⌃⌘Q, then turn the display off. The camera only starts when the
    /// screen wakes, so a lock screen that is already on would never try.
    static func lockNow() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
              let sym = dlsym(h, "SACLockScreenImmediate") else { return }
        typealias Lock = @convention(c) () -> Int32
        _ = unsafeBitCast(sym, to: Lock.self)()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            p.arguments = ["displaysleepnow"]
            try? p.run()
        }
    }

    /// Why the next wake would not try, ignoring the lock itself (Settings shows it). nil = ready.
    var readinessIssue: FaceUnlockPolicy.Denial? {
        guard enrolled else { return .notEnrolled }
        let f = FaceUnlockPolicy.Facts(now: Date(), screenLocked: true, lockedAt: Date(), lockWasManual: false,
                                       bootTime: Self.bootTime, lastPasswordUnlock: lastPasswordUnlock,
                                       consecutiveFailures: vault.consecutiveFailures, passwordTypedThisLock: false, enrolled: true,
                                       accessibilityTrusted: AXIsProcessTrusted(), presentationMode: AppModel.shared.presentationMode, network: nil)
        return FaceUnlockPolicy(settings: vault.settings).denial(f)
    }

    /// Everything goes: password, template, settings, log, file and key.
    func deleteEnrollment() {
        Keychain.set(nil, "faceunlock.password")
        Keychain.set(nil, "faceunlock.key")
        try? FileManager.default.removeItem(at: Self.vaultURL)
        vault = FaceVault()
        status = L("faceUnlock.deleted")
    }

    // MARK: Storage

    private func key() -> SymmetricKey {
        if let s = Keychain.get("faceunlock.key"), let d = Data(base64Encoded: s), d.count == 32 { return SymmetricKey(data: d) }
        let k = SymmetricKey(size: .bits256)
        Keychain.set(k.withUnsafeBytes { Data($0) }.base64EncodedString(), "faceunlock.key")
        return k
    }

    /// Nothing is created (no key, no file) until the user enrolls.
    private func load() {
        guard let d = try? Data(contentsOf: Self.vaultURL), Keychain.get("faceunlock.key") != nil,
              let v = try? FaceVault.open(d, with: key()) else { return }
        vault = v
    }

    func save() {
        guard vault.template != nil || FileManager.default.fileExists(atPath: Self.vaultURL.path),
              let d = try? vault.sealed(with: key()) else { return }
        try? FileManager.default.createDirectory(at: Self.vaultURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: Self.vaultURL, options: .atomic)
        chmod(Self.vaultURL.path, 0o600)
    }

    // MARK: System helpers

    static var screenLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
    }

    static var bootTime: Date {
        var tv = timeval(), size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &size, nil, 0) == 0 else { return Date() }
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec))
    }

    /// The login password, checked against the local directory before it is stored (FR-50, Glance does not).
    static func verify(password: String) -> Bool {
        guard let node = try? ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication)),
              let record = try? node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil) else { return false }
        return (try? record.verifyPassword(password)) != nil
    }

    /// Types into the lock screen: modifiers released, field cleared, 20 UTF-16 units per event, then Return.
    static func type(_ password: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        func key(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
                e?.flags = flags
                e?.post(tap: .cghidEventTap)
            }
        }
        CGEvent(source: src)?.flags = []
        key(124, .maskCommand)   // ⌘→
        key(51, .maskCommand)    // ⌘⌫
        var units = Array(password.utf16)
        defer { for i in units.indices { units[i] = 0 } }
        for chunk in stride(from: 0, to: units.count, by: 20) {
            guard screenLocked else { return }
            var part = Array(units[chunk..<min(units.count, chunk + 20)])
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                e?.keyboardSetUnicodeString(stringLength: part.count, unicodeString: &part)
                e?.post(tap: .cghidEventTap)
            }
            for i in part.indices { part[i] = 0 }
        }
        key(36)   // Return
    }
}

/// Spoken challenge: nothing can be drawn on the lock screen without the experimental SkyLight panel.
enum Speech {
    private static let synth = AVSpeechSynthesizer()
    static func say(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: L10n.language == "id" ? "id-ID" : "en-US")
        synth.speak(u)
    }
}

/// Built-in camera frames → Vision, ~10 per second, on its own queue. Virtual, USB and Continuity cameras are
/// refused (doc: Dylan vs Glance #3). Stops by itself after `duration` (8 s for unlocking).
nonisolated final class FaceCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct Frame: Sendable {
        var faceCount: Int
        var box: CGRect?
        var yaw: Double
        var pitch: Double
        var eyesOpen: Double
        var print: [Float]?
    }

    /// Read by the enrollment preview layer only; frames are never written anywhere.
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dylan.facecamera")
    private let onFrame: @Sendable (Frame) -> Void
    private var lastFrame: CFTimeInterval = 0

    init?(duration: TimeInterval = 8, onFrame: @escaping @Sendable (Frame) -> Void) {
        self.onFrame = onFrame
        super.init()
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let cam = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
                .devices.first(where: { $0.deviceType == .builtInWideAngleCamera && !$0.isContinuityCamera }),
              let input = try? AVCaptureDeviceInput(device: cam) else { return nil }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        guard session.canAddInput(input), session.canAddOutput(output) else { return nil }
        session.addInput(input); session.addOutput(output)
        session.commitConfiguration()
        queue.async { self.session.startRunning() }
        queue.asyncAfter(deadline: .now() + duration) { self.session.stopRunning() }
    }

    func stop() { queue.async { self.session.stopRunning() } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastFrame >= 0.1, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        let faces = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .upMirrored)
        try? handler.perform([faces])
        let found = faces.results ?? []
        guard found.count == 1, let f = found.first else {
            onFrame(Frame(faceCount: found.count, box: nil, yaw: 0, pitch: 0, eyesOpen: 1, print: nil)); return
        }
        let eyes = [f.landmarks?.leftEye, f.landmarks?.rightEye].compactMap { $0?.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) } }
        let open = eyes.isEmpty ? 1 : eyes.map(FaceGeometry.eyeOpenness).reduce(0, +) / Double(eyes.count)
        onFrame(Frame(faceCount: 1, box: f.boundingBox, yaw: (f.yaw?.doubleValue ?? 0) * 180 / .pi, pitch: (f.pitch?.doubleValue ?? 0) * 180 / .pi,
                      eyesOpen: open, print: Self.featurePrint(pixels, face: f.boundingBox)))
    }

    /// Feature print of the face crop (Vision; Float32 elements).
    static func featurePrint(_ pixels: CVPixelBuffer, face: CGRect) -> [Float]? {
        let req = VNGenerateImageFeaturePrintRequest()
        req.regionOfInterest = face.insetBy(dx: -face.width * 0.1, dy: -face.height * 0.1).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .upMirrored).perform([req])
        guard let o = req.results?.first as? VNFeaturePrintObservation, o.elementType == .float else { return nil }
        return o.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(o.elementCount)) }
    }
}
