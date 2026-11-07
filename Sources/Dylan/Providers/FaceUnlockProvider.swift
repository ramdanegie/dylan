import AppKit
import AVFoundation
import CryptoKit
import DylanCore
import IOKit.hid
import LocalAuthentication
import OpenDirectory
import Vision

/// Face Unlock (PRD §F15, FR-50–55): experimental, off by default, never on without an enrollment the user
/// started. See docs/face-unlock.md for the threat model. In short: built-in camera only, a random spoken
/// challenge (look left, blink…) with identity checked on every frame, Apple-style limits (5 failures, 48 h,
/// never after a restart, one password per lock), the password verified before it is stored, and a local
/// audit log without images. From Glance (replica/recon.md): several identities, guided enrollment, a short grace
/// for blurred frames, the phone-bezel cue, a scan island on the lock screen, space to retry, Touch ID before
/// settings that make it open more easily, changing the stored password, and a test that only measures.
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
    @ObservationIgnored private var spaceKey: SpaceKey?
    @ObservationIgnored private var lastAttemptEnd = Date.distantPast

    private static var vaultURL: URL { Bridge.socketURL.deletingLastPathComponent().appendingPathComponent("face.sealed") }

    var enrolled: Bool { !vault.identities.isEmpty && Keychain.exists("faceunlock.password") }
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
        if enabled, vault.settings.spaceRetry, spaceKey == nil {
            spaceKey = SpaceKey { FaceUnlockProvider.shared.spacePressed() }
        }
    }

    private func didUnlock() {
        spaceKey?.stop(); spaceKey = nil
        // Unlocked by hand (Touch ID, password) while an attempt still ran: end it quietly, no failure, no island.
        if challenge != nil, !practicing {
            watchdog?.cancel(); watchdog = nil
            camera?.stop(); camera = nil
            challenge = nil
        }
        FaceScanIsland.shared.hide()
        guard !vault.identities.isEmpty else { lockedAt = nil; return }   // never enrolled: nothing to record
        let now = Date()
        unlockCheck?.cancel(); unlockCheck = nil
        let m = AppModel.shared
        if typedThisLock {
            record(.init(at: now, result: .unlocked))
            vault.consecutiveFailures = 0
            // D21: Compact "Wajah · 09.12", then an automatic Peek with the score, the time and how long it was locked.
            let time = now.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale))
            let locked = DurationFormat.long(now.timeIntervalSince(lockedAt ?? now), language: L10n.language)
            m.center.post(Activity(id: "faceunlock", kind: .notify, priority: .p1, state: .success, symbol: "faceid",
                                   label: L("faceUnlock.short"), value: time, detail: L("faceUnlock.unlockedDetail", time, locked),
                                   progress: lastIdentity, url: "faceunlock:history", startedAt: now), now: now)
            m.autoPeekUntil = now.addingTimeInterval(4)
            if m.notchState == .closed || m.notchState == .compact { m.notchState = .peek }
            m.scheduleTick()
        } else {
            // A manual unlock (password or Touch ID — macOS does not say which) resets the failures.
            lastPasswordUnlock = now
            vault.consecutiveFailures = 0
            if let notice = pendingNotice {
                m.center.post(Activity(id: "faceunlock", kind: .notify, priority: .p1, state: .failure, symbol: "xmark",
                                       label: L("faceUnlock.short"), value: L("faceUnlock.off"), detail: notice,
                                       url: "faceunlock:history", startedAt: now), now: now)
                m.scheduleTick()
            }
        }
        pendingNotice = nil
        lockedAt = nil
        typedThisLock = false
        save()
    }

    private func screenWoke() {
        guard enabled, Self.screenLocked else { return }
        attempt()
    }

    /// Space at the lock screen (Glance): another try without sleeping the display. `SpaceKey` only calls this
    /// while nothing else was typed since the lock, so the field holds just this space: it is erased.
    private func spacePressed() {
        guard enabled, camera == nil, Self.screenLocked, Date().timeIntervalSince(lastAttemptEnd) > 1 else { return }
        Self.pressKey(51)   // ⌫
        attempt(manual: true)
    }

    func disable() {
        vault.settings.enabled = false
        save()
        camera?.stop(); camera = nil
        spaceKey?.stop(); spaceKey = nil
    }

    // MARK: One attempt (≤ 6 s of camera)

    private var facts: FaceUnlockPolicy.Facts {
        FaceUnlockPolicy.Facts(now: Date(), screenLocked: Self.screenLocked, lockedAt: lockedAt, lockWasManual: lockManual,
                               bootTime: Self.bootTime, lastPasswordUnlock: lastPasswordUnlock, consecutiveFailures: vault.consecutiveFailures,
                               passwordTypedThisLock: typedThisLock, enrolled: enrolled, identitiesOn: vault.canMatch,
                               accessibilityTrusted: AXIsProcessTrusted(),
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
    /// Match score of the attempt that typed the password, for the notch (D21 "skor 0,93").
    @ObservationIgnored private var lastIdentity: Double = 0
    /// Nothing Dylan shows is visible on the lock screen, so a "turned off" notice waits for the next unlock (D21).
    @ObservationIgnored private var pendingNotice: String?
    /// Challenge step the island shows.
    @ObservationIgnored private var shownStep = 0

    /// `manual`: the user pressed space, so a refusal is shown on the island instead of staying silent.
    private func attempt(manual: Bool = false) {
        guard camera == nil, !vault.identities.isEmpty else { return }
        if let d = FaceUnlockPolicy(settings: vault.settings).denial(facts) {
            if !deniedLoggedThisLock { deniedLoggedThisLock = true; record(.init(at: Date(), result: .denied, reason: d.rawValue)) }
            if manual, vault.settings.lockScreenIsland { FaceScanIsland.shared.show(.failed(L("faceUnlock.denial.\(d.rawValue)")), hideAfter: 3) }
            return
        }
        beginChallenge()
    }

    // MARK: Practice (in "Test your face"): the real challenge while unlocked. Nothing is typed, logged or counted.

    struct Practice: Equatable {
        var step: String?
        var index = 1
        var count = 2
        var passed: Bool?
        var reason: String?
        var trace: LivenessChallenge.Trace?
    }
    var practice: Practice?
    @ObservationIgnored private var practicing = false

    func startPractice() {
        guard camera == nil, labCamera == nil, enrollCamera == nil, vault.canMatch else { return }
        practicing = true
        beginChallenge()
    }

    private func beginChallenge() {
        var g = SystemRandomNumberGenerator()
        let c = LivenessChallenge.random(using: &g)
        challenge = c
        tracker = FaceGeometry.Tracker()
        bestIdentity = 0
        startedAt = Date()
        shownStep = 0
        if practicing { practice = Practice(step: L("faceUnlock.step.\(c.steps[0].rawValue)"), index: 1, count: c.steps.count) }
        let island = !practicing && vault.settings.lockScreenIsland && FaceScanIsland.shared.show(Self.scanning(c, 0))
        FaceScanIsland.shared.spaceHint = spaceKey != nil
        if vault.settings.speak || !island { Speech.say(c.steps.map { L("faceUnlock.step.\($0.rawValue)") }.joined(separator: ", ")) }
        camera = FaceCamera(detectDevices: true) { frame in
            DispatchQueue.main.async { MainActor.assumeIsolated { FaceUnlockProvider.shared.attemptFrame(frame) } }
        }
        guard camera != nil else {
            challenge = nil
            if practicing { practicing = false; practice = Practice(passed: false, reason: "noCamera"); return }
            record(.init(at: Date(), result: .failed, reason: "noCamera", steps: c.steps))
            if vault.settings.lockScreenIsland { FaceScanIsland.shared.show(.failed(L("faceUnlock.reason.noCamera")), hideAfter: 3) }
            return
        }
        // No frames at all (camera busy or blocked) must not leave the attempt open forever.
        arm(after: LivenessChallenge.window + 2) { p in
            guard let c = p.challenge else { return }
            p.finish(passed: false, reason: LivenessChallenge.Reason.timeout.rawValue, identity: p.bestIdentity, steps: c.steps, trace: c.trace)
        }
    }

    private static func scanning(_ c: LivenessChallenge, _ step: Int) -> FaceScanIsland.Phase {
        .scanning(step: L("faceUnlock.step.\(c.steps[step].rawValue)"), index: step + 1, count: c.steps.count)
    }

    private func attemptFrame(_ frame: FaceCamera.Frame) {
        guard camera != nil, var c = challenge else { return }
        let identity = frame.print.map { FaceMatcher.identity($0, vault.identities) } ?? 0
        bestIdentity = max(bestIdentity, identity)
        let head = vault.poseSigns.apply(yaw: frame.yaw, pitch: frame.pitch)
        let sample = LivenessChallenge.Sample(time: Date().timeIntervalSince(startedAt), faceCount: frame.faceCount,
                                              trackID: frame.box.map { tracker.track($0) }, yaw: head.yaw, pitch: head.pitch,
                                              eyesOpen: frame.eyesOpen, identity: identity, device: frame.device)
        let outcome = c.feed(sample)
        challenge = c
        switch outcome {
        case .inProgress(let step):
            if step != shownStep, step < c.steps.count {
                shownStep = step
                if practicing {
                    practice = Practice(step: L("faceUnlock.step.\(c.steps[step].rawValue)"), index: step + 1, count: c.steps.count)
                } else if vault.settings.lockScreenIsland {
                    FaceScanIsland.shared.show(Self.scanning(c, step))
                }
            }
            return
        case .passed: finish(passed: true, reason: nil, identity: bestIdentity, steps: c.steps, trace: c.trace)
        case .failed(let r): finish(passed: false, reason: r.rawValue, identity: bestIdentity, steps: c.steps, trace: c.trace)
        }
    }

    private func arm(after seconds: TimeInterval, _ f: @escaping @MainActor (FaceUnlockProvider) -> Void) {
        watchdog?.cancel()
        let w = DispatchWorkItem { MainActor.assumeIsolated { f(FaceUnlockProvider.shared) } }
        watchdog = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    private func finish(passed: Bool, reason: String?, identity: Double, steps: [LivenessChallenge.Step], trace: LivenessChallenge.Trace? = nil) {
        watchdog?.cancel(); watchdog = nil
        camera?.stop(); camera = nil
        challenge = nil
        Self.haptic(passed)
        if practicing {
            practicing = false
            practice = Practice(step: nil, passed: passed, reason: reason, trace: trace)
            return
        }
        lastAttemptEnd = Date()
        guard passed else {
            vault.consecutiveFailures += 1
            record(.init(at: Date(), result: .failed, reason: reason, identity: identity, steps: steps, trace: trace))
            if vault.consecutiveFailures >= FaceUnlockPolicy.maxFailures { pendingNotice = L("faceUnlock.offTooMany") }
            if vault.settings.lockScreenIsland { FaceScanIsland.shared.show(.failed(Self.reasonText(reason)), hideAfter: 4) }
            return
        }
        lastIdentity = identity
        // Re-check right before typing: unlocked meanwhile, or the policy changed (e.g. Presentation Mode).
        guard Self.screenLocked, FaceUnlockPolicy(settings: vault.settings).denial(facts) == nil,
              let password = Keychain.get("faceunlock.password") else { return }
        typedThisLock = true
        save()
        // The island lives in its own SkyLight space above the lock screen and may hold the keyboard: close it first
        // (all four passes in a test typed the password and stayed locked while it was up).
        FaceScanIsland.shared.hide()
        Self.type(password)
        // Still locked a few seconds later: the stored password is wrong (changed since enrollment). Stop typing it.
        unlockCheck?.cancel()
        let w = DispatchWorkItem { MainActor.assumeIsolated {
            let p = FaceUnlockProvider.shared
            guard Self.screenLocked, p.typedThisLock else { return }
            p.record(.init(at: Date(), result: .failed, reason: "passwordRejected", identity: identity, steps: steps))
            p.typedThisLock = false   // the unlock that follows is by hand, not by face
            p.disable()
            p.pendingNotice = L("faceUnlock.offPassword")
        } }
        unlockCheck = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: w)
    }

    private func record(_ e: FaceUnlockEvent) { vault.log.append(e); save() }

    /// A policy denial, a liveness reason, or a camera/password problem, in words.
    static func reasonText(_ r: String?) -> String {
        guard let r else { return "" }
        if let d = FaceUnlockPolicy.Denial(rawValue: r) { return L("faceUnlock.denial.\(d.rawValue)") }
        let known: Set<String> = ["timeout", "multipleFaces", "faceChanged", "wrongPerson", "wrongOrder", "spoof", "noCamera", "passwordRejected"]
        return known.contains(r) ? L("faceUnlock.reason.\(r)") : r
    }

    /// The log as plain text for the clipboard (no images or passwords are in it to begin with).
    func copyLog() {
        let lines = vault.log.events.map { e -> String in
            var parts = [e.at.formatted(date: .abbreviated, time: .standard), L("faceUnlock.result.\(e.result.rawValue)")]
            if let r = e.reason { parts.append(Self.reasonText(r)) }
            if let i = e.identity { parts.append(String(format: "%.2f", i)) }
            if !e.steps.isEmpty { parts.append(e.steps.map(\.rawValue).joined(separator: "→")) }
            if let t = e.trace { parts.append(Self.traceText(t)) }
            return parts.joined(separator: " · ")
        }
        var head = ["Dylan \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") Face Unlock",
                    L(vault.settings.enabled ? "faceUnlock.island.on" : "faceUnlock.island.off")]
        if let issue = readinessIssue { head.append(L("faceUnlock.denial.\(issue.rawValue)")) }
        // The last practice is not in the log (nothing was at stake), but it is what tuning needs.
        if let p = practice, let ok = p.passed {
            head.append(L("faceUnlock.practice") + ": " + (ok ? L("faceUnlock.practicePassed") : L("faceUnlock.practiceFailed", Self.reasonText(p.reason)))
                        + (p.trace.map { " · " + Self.traceText($0) } ?? ""))
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString((head + lines).joined(separator: "\n"), forType: .string)
        status = L("faceUnlock.logCopied")
    }

    /// "left-right −4…18° · up-down −6…9° · …": what the camera saw, for the log and the test.
    static func traceText(_ t: LivenessChallenge.Trace) -> String {
        let deg: (Double) -> String = { "\(Int($0.rounded()))°" }
        let num: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(2)).locale(L10n.locale)) }
        return L("faceUnlock.trace", deg(t.yaw.lowerBound), deg(t.yaw.upperBound), deg(t.pitch.lowerBound), deg(t.pitch.upperBound),
                 num(t.minEyes), num(t.bestIdentity), "\(t.matched)/\(t.frames)") + (t.closedIdentity.map { " · " + L("faceUnlock.traceClosed", num($0)) } ?? "")
    }

    /// A tap on the trackpad (felt only with a finger on it), as Glance does.
    private static func haptic(_ passed: Bool) {
        NSHapticFeedbackManager.defaultPerformer.perform(passed ? .levelChange : .generic, performanceTime: .now)
    }

    // MARK: Enrollment (FR-50, design D19: risks → camera → password → ready)

    /// Frames kept for the template: three per head direction.
    static var enrollTarget: Int { PoseCoverage.total }
    enum EnrollState: Equatable { case idle, capturing, captured, failed(String) }
    var enrollState: EnrollState = .idle
    var enrollCount = 0
    /// Faces in the latest frame, so the wizard can say "only one face".
    var enrollFaces = 0
    /// Directions captured so far, the live head position (-1…1, mirrored like the preview; nil = no face), and
    /// whether the head is turned too far (Glance 1.0.1/1.2.0).
    var coverage = PoseCoverage()
    var enrollHead: CGPoint?
    var enrollTooFar = false
    /// The running camera, for the wizard's live preview (never stored).
    private(set) var enrollCamera: FaceCamera?
    @ObservationIgnored private var lastEnrollFrame = Date.distantPast
    @ObservationIgnored private var enrollPoses: [Int] = []
    /// Learned in this enrollment from the first "left" and "up" turns; saved with it.
    @ObservationIgnored private var enrollSigns = PoseSigns()

    /// Step 2: the camera runs with a preview while the user turns their head; one print every 0.25 s, kept
    /// only when its direction still needs one.
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
        stopLab()
        enrollPrints = []
        enrollPoses = []
        enrollCount = 0
        coverage = PoseCoverage()
        enrollSigns = PoseSigns()
        enrollHead = nil
        enrollTooFar = false
        enrollState = .capturing
        enrollCamera = FaceCamera(duration: 45) { frame in
            DispatchQueue.main.async { MainActor.assumeIsolated { FaceUnlockProvider.shared.enrollFrame(frame) } }
        }
        guard enrollCamera != nil else { enrollState = .failed(L("faceUnlock.noCamera")); return }
        arm(after: 45) { $0.endEnrollCapture() }
    }

    private func enrollFrame(_ frame: FaceCamera.Frame) {
        guard enrollState == .capturing else { return }
        enrollFaces = frame.faceCount
        guard frame.faceCount == 1 else { enrollHead = nil; return }
        let reading = PoseCoverage.classify(yaw: frame.yaw, pitch: frame.pitch, signs: &enrollSigns, asking: coverage.missing)
        // Mirrored like the preview: the user's left is drawn on the left. Signs learned so far, else the last
        // enrollment's. Smoothed so the dot glides instead of jitters.
        let known = PoseSigns(yaw: enrollSigns.yaw ?? vault.poseSigns.yaw, pitch: enrollSigns.pitch ?? vault.poseSigns.pitch)
        let head = known.apply(yaw: frame.yaw, pitch: frame.pitch)
        let target = CGPoint(x: max(-1, min(1, -head.yaw / PoseCoverage.tooFar)), y: max(-1, min(1, -head.pitch / PoseCoverage.tooFar)))
        let last = enrollHead ?? target
        enrollHead = CGPoint(x: last.x + (target.x - last.x) * 0.5, y: last.y + (target.y - last.y) * 0.5)
        enrollTooFar = reading == .tooFar
        guard case .pose(let pose) = reading, let f = frame.print, Date().timeIntervalSince(lastEnrollFrame) >= 0.25, coverage.add(pose) else { return }
        lastEnrollFrame = Date()
        enrollPrints.append(f)
        enrollPoses.append(pose.rawValue)
        enrollCount = enrollPrints.count
        if coverage.complete { endEnrollCapture() }
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
        enrollPoses = []
        enrollCount = 0
        enrollHead = nil
        enrollState = .idle
    }

    /// Step 3: the password is verified before anything is stored; then the template is sealed and the feature is on.
    func completeEnrollment(password: String) -> String? {
        guard enrollState == .captured else { return L("faceUnlock.enrollFailed") }
        guard Self.verify(password: password) else { return L("faceUnlock.wrongPassword") }
        guard let t = FaceMatcher.enroll(enrollPrints, poses: enrollPoses, now: Date()) else { return L("faceUnlock.enrollFailed") }
        Keychain.set(password, "faceunlock.password")
        vault.identities = [FaceIdentity(name: "", template: t)]
        keepSigns()
        vault.settings.enabled = true
        lastPasswordUnlock = Date()   // the login password was just verified, in this boot
        save()
        status = L("faceUnlock.enrolled", enrollPrints.count)
        cancelEnroll()
        return nil
    }

    private func keepSigns() {
        if let y = enrollSigns.yaw { vault.poseSigns.yaw = y }
        if let p = enrollSigns.pitch { vault.poseSigns.pitch = p }
    }

    // MARK: Identities (Glance: glasses, a mask, dim light, someone you trust)

    /// Another look for the same Mac. The password is already stored; Settings asked for Touch ID first.
    func addIdentity(name: String) -> String? {
        guard enrollState == .captured, enrolled, vault.identities.count < FaceVault.maxIdentities,
              let t = FaceMatcher.enroll(enrollPrints, poses: enrollPoses, now: Date()) else { return L("faceUnlock.enrollFailed") }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        vault.identities.append(FaceIdentity(name: trimmed.isEmpty ? L("faceUnlock.identity.other") : trimmed, template: t))
        keepSigns()
        save()
        status = L("faceUnlock.identityAdded", vault.identities.last!.name)
        cancelEnroll()
        return nil
    }

    func setIdentity(_ id: UUID, enabled: Bool) {
        guard let i = vault.identities.firstIndex(where: { $0.id == id }) else { return }
        vault.identities[i].enabled = enabled
        save()
    }

    /// The last identity takes everything with it, as "Delete" does.
    func deleteIdentity(_ id: UUID) {
        guard vault.identities.count > 1 else { deleteEnrollment(); return }
        vault.identities.removeAll { $0.id == id }
        save()
    }

    static func displayName(_ i: FaceIdentity) -> String { i.name.isEmpty ? L("faceUnlock.identity.main") : i.name }

    /// A new login password without enrolling again (Glance 1.2.0), verified like the first one.
    func changePassword(_ password: String) -> String? {
        guard Self.verify(password: password) else { return L("faceUnlock.wrongPassword") }
        Keychain.set(password, "faceunlock.password")
        lastPasswordUnlock = Date()
        vault.consecutiveFailures = 0
        save()
        status = L("faceUnlock.passwordSaved")
        return nil
    }

    // MARK: Touch ID before loosening (Glance keeps its settings behind Touch ID)

    @ObservationIgnored private var authorizedUntil = Date.distantPast
    /// The pending request; a second click while Touch ID is up is ignored.
    @ObservationIgnored private var authContext: LAContext?

    /// Touch ID (or the Mac password) before anything that lets Face Unlock open more easily: turning it on, a longer
    /// lock limit, another identity, a new password, space to retry. Two minutes of grace so a stepper does not ask
    /// on every click. Turning things off never asks.
    func authorize(_ action: @escaping @MainActor @Sendable () -> Void) {
        if Date() < authorizedUntil { action(); return }
        guard authContext == nil else { return }
        let ctx = LAContext()
        authContext = ctx
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L("faceUnlock.authReason")) { ok, _ in
            Task { @MainActor in
                let p = FaceUnlockProvider.shared
                p.authContext = nil
                guard ok else { return }
                p.authorizedUntil = Date().addingTimeInterval(120)
                action()
            }
        }
    }

    // MARK: Space to retry (Input Monitoring)

    static var inputMonitoringAllowed: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    /// Shows the system prompt the first time; later it only answers.
    @discardableResult static func requestInputMonitoring() -> Bool { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    // MARK: Test (Glance's Face Lab): live scores, nothing unlocks, nothing is stored

    struct LabReading: Equatable {
        var faces: Int
        var scores: [UUID: Double]
        var yaw: Double
        var pitch: Double
        var eyesOpen: Double
        var device: Bool
        /// Since the test started: how far each way, the deepest blink, the best score.
        var peaks = LivenessChallenge.Trace()
    }
    var lab: LabReading?
    private(set) var labCamera: FaceCamera?
    @ObservationIgnored private var labStop: DispatchWorkItem?

    func startLab() {
        guard labCamera == nil, camera == nil, enrollCamera == nil else { return }
        practice = nil
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { status = L("faceUnlock.noCamera"); return }
        lab = nil
        labCamera = FaceCamera(duration: 10, detectDevices: true) { frame in
            DispatchQueue.main.async { MainActor.assumeIsolated { FaceUnlockProvider.shared.labFrame(frame) } }
        }
        guard labCamera != nil else { status = L("faceUnlock.noCamera"); return }
        let w = DispatchWorkItem { MainActor.assumeIsolated { FaceUnlockProvider.shared.stopLab() } }
        labStop = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: w)
    }

    func stopLab() {
        labStop?.cancel(); labStop = nil
        labCamera?.stop(); labCamera = nil
    }

    private func labFrame(_ f: FaceCamera.Frame) {
        guard labCamera != nil else { return }
        var scores: [UUID: Double] = [:]
        if let p = f.print { for i in vault.identities { scores[i.id] = FaceMatcher.identity(p, i.template) } }
        var peaks = lab?.peaks ?? .init()
        let head = vault.poseSigns.apply(yaw: f.yaw, pitch: f.pitch)
        if f.faceCount == 1 {
            peaks.frames += 1
            peaks.yaw = min(peaks.yaw.lowerBound, head.yaw)...max(peaks.yaw.upperBound, head.yaw)
            peaks.pitch = min(peaks.pitch.lowerBound, head.pitch)...max(peaks.pitch.upperBound, head.pitch)
            peaks.minEyes = min(peaks.minEyes, f.eyesOpen)
            peaks.bestIdentity = max(peaks.bestIdentity, scores.values.max() ?? 0)
        }
        lab = LabReading(faces: f.faceCount, scores: scores, yaw: head.yaw, pitch: head.pitch, eyesOpen: f.eyesOpen, device: f.device, peaks: peaks)
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
                                       identitiesOn: vault.canMatch, accessibilityTrusted: AXIsProcessTrusted(), presentationMode: AppModel.shared.presentationMode, network: nil)
        return FaceUnlockPolicy(settings: vault.settings).denial(f)
    }

    /// Everything goes: password, template, settings, log, file and key.
    func deleteEnrollment() {
        stopLab()
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
        guard let d = try? Data(contentsOf: Self.vaultURL) else { return }
        if Keychain.get("faceunlock.key") != nil, let v = try? FaceVault.open(d, with: key()) { vault = v; return }
        // No key, or a vault this build cannot read: the next save would overwrite it with an empty one. Keep it aside.
        let aside = Self.vaultURL.appendingPathExtension("unreadable")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: Self.vaultURL, to: aside)
    }

    func save() {
        guard !vault.identities.isEmpty || FileManager.default.fileExists(atPath: Self.vaultURL.path),
              let d = try? vault.sealed(with: key()) else { return }
        try? FileManager.default.createDirectory(at: Self.vaultURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: Self.vaultURL, options: .atomic)
        chmod(Self.vaultURL.path, 0o600)
    }

    // MARK: System helpers

    nonisolated static var screenLocked: Bool {
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

    nonisolated static func pressKey(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Types into the lock screen, off the main thread and paced like a fast typist: a short wait for the lock screen to
    /// have the keyboard, the field cleared (⌘→ ⌘⌫), one character per event, then Return. A burst of multi-character
    /// events did not unlock in a real test. Each buffer is zeroed after use; stops if the screen unlocks meanwhile.
    nonisolated static func type(_ password: String) {
        DispatchQueue.global(qos: .userInteractive).async {
            let src = CGEventSource(stateID: .hidSystemState)
            usleep(300_000)
            pressKey(124, .maskCommand)   // ⌘→
            usleep(30_000)
            pressKey(51, .maskCommand)    // ⌘⌫
            usleep(80_000)
            for ch in password {
                guard screenLocked else { return }
                var part = Array(String(ch).utf16)
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                    e?.flags = []
                    e?.keyboardSetUnicodeString(stringLength: part.count, unicodeString: &part)
                    e?.post(tap: .cghidEventTap)
                }
                for i in part.indices { part[i] = 0 }
                usleep(12_000)
            }
            usleep(150_000)
            guard screenLocked else { return }
            pressKey(36)   // Return
        }
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
        var device = false
    }

    /// Read by the enrollment preview layer only; frames are never written anywhere.
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dylan.facecamera")
    private let onFrame: @Sendable (Frame) -> Void
    private var lastFrame: CFTimeInterval = 0
    /// Also look for a phone or tablet around the face (unlock and test only; enrollment needs speed).
    private let detectDevices: Bool
    /// Where the head was in the first frame (camera queue only): yaw and pitch are reported from there, in
    /// Vision's own signs; `PoseSigns` turns them into left/up. A first frame already turned far is not a rest pose.
    private var base: (yaw: Double, pitch: Double)?

    init?(duration: TimeInterval = 8, detectDevices: Bool = false, onFrame: @escaping @Sendable (Frame) -> Void) {
        self.onFrame = onFrame
        self.detectDevices = detectDevices
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
        // Faces with continuous yaw and pitch (revision 3; the landmarks request alone gives yaw in 45° steps and no
        // pitch), then the landmarks of exactly those faces.
        let detect = VNDetectFaceRectanglesRequest()
        detect.revision = VNDetectFaceRectanglesRequestRevision3
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .upMirrored)
        try? handler.perform([detect])
        let found = detect.results ?? []
        guard found.count == 1, let f = found.first else {
            onFrame(Frame(faceCount: found.count, box: nil, yaw: 0, pitch: 0, eyesOpen: 1, print: nil)); return
        }
        let marks = VNDetectFaceLandmarksRequest()
        marks.inputFaceObservations = found
        let rects = VNDetectRectanglesRequest()
        rects.minimumAspectRatio = 0.3
        rects.minimumSize = 0.15
        rects.minimumConfidence = 0.6
        rects.maximumObservations = 4
        try? handler.perform(detectDevices ? [marks, rects] : [marks])
        let lm = marks.results?.first?.landmarks
        func points(_ r: VNFaceLandmarkRegion2D?) -> [CGPoint] { r?.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) } ?? [] }
        let eyes = [lm?.leftEye, lm?.rightEye].compactMap { $0 }.map(points)
        let open = eyes.isEmpty ? 1 : eyes.map(FaceGeometry.eyeOpenness).reduce(0, +) / Double(eyes.count)
        let yaw = (f.yaw?.doubleValue ?? 0) * 180 / .pi, pitch = (f.pitch?.doubleValue ?? 0) * 180 / .pi
        let b = base ?? (abs(yaw) <= 20 ? yaw : 0, abs(pitch) <= 25 ? pitch : 0)
        base = b
        let head = (yaw: yaw - b.yaw, pitch: pitch - b.pitch)
        let device = detectDevices && FaceGeometry.framedByDevice(face: f.boundingBox, rects: (rects.results ?? []).map(\.boundingBox))
        onFrame(Frame(faceCount: 1, box: f.boundingBox, yaw: head.yaw, pitch: head.pitch,
                      eyesOpen: open, print: Self.featurePrint(pixels, face: f.boundingBox), device: device))
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

/// The space bar while the Mac is locked (Glance). The lock screen turns on Secure Event Input, which hides keys from
/// event taps, so this reads the keyboard through IOHIDManager (Input Monitoring). It runs only between lock and
/// unlock, looks only at whether a key is the space bar, and never keeps any key. Once any other key is pressed
/// the user is typing their password, and space stops meaning "try again" until the next lock (a password that
/// starts with a space cannot use this).
final class SpaceKey {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let onSpace: @MainActor () -> Void
    private var typing = false

    init?(onSpace: @escaping @MainActor () -> Void) {
        self.onSpace = onSpace
        guard FaceUnlockProvider.inputMonitoringAllowed else { return nil }
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            let e = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(e), usage = IOHIDElementGetUsage(e)
            // Usages 4…231 are the real keys; the rest are reports for rollover and the like.
            guard let ctx, page == UInt32(kHIDPage_KeyboardOrKeypad), (4...231).contains(usage), IOHIDValueGetIntegerValue(value) == 1 else { return }
            MainActor.assumeIsolated { Unmanaged<SpaceKey>.fromOpaque(ctx).takeUnretainedValue().key(usage) }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return nil
        }
    }

    private func key(_ usage: UInt32) {
        if usage == UInt32(kHIDUsage_KeyboardSpacebar) {
            if !typing { onSpace() }
        } else if usage < 224 {   // 224…231 are modifiers: tapping Shift to wake the screen is not typing
            typing = true
        }
    }

    func stop() {
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}
