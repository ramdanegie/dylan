import Foundation

/// Face Unlock safety rules (PRD §F15, FR-52; docs/face-unlock.md). Pure logic: the app feeds facts,
/// this decides whether the camera may even turn on. Stricter than Glance on purpose.
public struct FaceUnlockPolicy: Equatable, Sendable {
    public struct Settings: Equatable, Sendable, Codable {
        public var enabled = false
        public var maxLockedMinutes = 60
        public var trustedNetworksOnly = false
        public var trustedNetworks: Set<String> = []
        public init() {}
    }

    /// Everything the app knows at the moment the screen wakes.
    public struct Facts: Equatable, Sendable {
        public var now: Date
        public var screenLocked: Bool          // from CGSessionCopyCurrentDictionary, not the notification
        public var lockedAt: Date?
        public var lockWasManual: Bool
        public var bootTime: Date
        public var lastPasswordUnlock: Date?   // nil = none since boot
        public var consecutiveFailures: Int
        public var passwordTypedThisLock: Bool
        public var enrolled: Bool
        public var accessibilityTrusted: Bool
        public var presentationMode: Bool
        public var network: String?
        public init(now: Date, screenLocked: Bool, lockedAt: Date?, lockWasManual: Bool = false, bootTime: Date,
                    lastPasswordUnlock: Date?, consecutiveFailures: Int = 0, passwordTypedThisLock: Bool = false,
                    enrolled: Bool = true, accessibilityTrusted: Bool = true, presentationMode: Bool = false, network: String? = nil) {
            self.now = now; self.screenLocked = screenLocked; self.lockedAt = lockedAt; self.lockWasManual = lockWasManual
            self.bootTime = bootTime; self.lastPasswordUnlock = lastPasswordUnlock; self.consecutiveFailures = consecutiveFailures
            self.passwordTypedThisLock = passwordTypedThisLock; self.enrolled = enrolled
            self.accessibilityTrusted = accessibilityTrusted; self.presentationMode = presentationMode; self.network = network
        }
    }

    public enum Denial: String, Sendable, Equatable {
        case disabled, notEnrolled, notLocked, firstUnlockSinceBoot, passwordTooOld, lockedTooLong
        case tooManyFailures, alreadyTriedThisLock, justLockedManually, untrustedNetwork, presentationMode, noAccessibility
    }

    /// Apple's own limits for biometrics: 5 failed matches, 48 h without the password.
    public static let maxFailures = 5
    public static let passwordMaxAge: TimeInterval = 48 * 3600
    /// Do not unlock again right after the user locked on purpose while still looking at the screen.
    public static let manualLockGrace: TimeInterval = 10

    public var settings: Settings
    public init(settings: Settings) { self.settings = settings }

    /// nil = allowed to start the camera. Order matters only for the reason shown in the log.
    public func denial(_ f: Facts) -> Denial? {
        if !settings.enabled { return .disabled }
        if !f.enrolled { return .notEnrolled }
        if !f.screenLocked { return .notLocked }
        if !f.accessibilityTrusted { return .noAccessibility }
        if f.presentationMode { return .presentationMode }
        guard let lastPassword = f.lastPasswordUnlock, lastPassword >= f.bootTime else { return .firstUnlockSinceBoot }
        if f.now.timeIntervalSince(lastPassword) >= Self.passwordMaxAge { return .passwordTooOld }
        if f.consecutiveFailures >= Self.maxFailures { return .tooManyFailures }
        if f.passwordTypedThisLock { return .alreadyTriedThisLock }
        if let locked = f.lockedAt {
            if f.now.timeIntervalSince(locked) >= TimeInterval(settings.maxLockedMinutes * 60) { return .lockedTooLong }
            if f.lockWasManual && f.now.timeIntervalSince(locked) < Self.manualLockGrace { return .justLockedManually }
        }
        if settings.trustedNetworksOnly && !(f.network.map(settings.trustedNetworks.contains) ?? false) { return .untrustedNetwork }
        return nil
    }
}

/// Randomised challenge-response liveness: a replayed video cannot follow prompts it has never seen.
/// The app turns each camera frame into a `Sample` (Vision yaw/pitch, eye openness, identity score, face track).
public struct LivenessChallenge: Equatable, Sendable {
    public enum Step: String, Sendable, CaseIterable, Codable {
        case lookLeft, lookRight, lookUp, blink
    }

    public struct Sample: Equatable, Sendable {
        public var time: TimeInterval        // seconds since the challenge started
        public var faceCount: Int
        public var trackID: Int?             // same physical face across frames
        public var yaw: Double               // degrees, + = user's left
        public var pitch: Double             // degrees, + = up
        public var eyesOpen: Double          // 0 closed … 1 open
        public var identity: Double          // similarity to the enrolled face, 0…1
        public init(time: TimeInterval, faceCount: Int = 1, trackID: Int? = 1, yaw: Double = 0, pitch: Double = 0,
                    eyesOpen: Double = 1, identity: Double = 0.9) {
            self.time = time; self.faceCount = faceCount; self.trackID = trackID; self.yaw = yaw; self.pitch = pitch
            self.eyesOpen = eyesOpen; self.identity = identity
        }
    }

    public enum Outcome: Equatable, Sendable {
        case inProgress(step: Int)
        case passed
        case failed(Reason)
    }

    public enum Reason: String, Sendable, Equatable {
        case timeout, multipleFaces, faceChanged, wrongPerson, wrongOrder
    }

    public static let window: TimeInterval = 6
    public static let turnDegrees: Double = 15
    public static let blinkClosed: Double = 0.2

    public let steps: [Step]
    public let identityThreshold: Double
    private(set) var current = 0
    private(set) var track: Int?
    private(set) var eyesWereClosed = false
    public private(set) var outcome: Outcome = .inProgress(step: 0)

    public init(steps: [Step], identityThreshold: Double = 0.66) {
        self.steps = steps; self.identityThreshold = identityThreshold
    }

    /// Two different random steps; at most one blink so the prompt stays quick.
    public static func random<G: RandomNumberGenerator>(using g: inout G) -> LivenessChallenge {
        let first = Step.allCases.randomElement(using: &g)!
        let second = Step.allCases.filter { $0 != first }.randomElement(using: &g)!
        return LivenessChallenge(steps: [first, second])
    }

    public mutating func feed(_ s: Sample) -> Outcome {
        guard case .inProgress = outcome else { return outcome }
        if s.time > Self.window { return finish(.failed(.timeout)) }
        if s.faceCount > 1 { return finish(.failed(.multipleFaces)) }
        guard s.faceCount == 1 else { return outcome }                    // face briefly lost: keep waiting
        if let t = track, s.trackID != t { return finish(.failed(.faceChanged)) }
        track = track ?? s.trackID
        // Identity is checked on every frame, not once: a different person cannot finish someone else's challenge.
        if s.identity < identityThreshold { return finish(.failed(.wrongPerson)) }

        let step = steps[current]
        if Self.satisfies(step, s, eyesWereClosed: &eyesWereClosed) {
            current += 1
            eyesWereClosed = false
            if current == steps.count { return finish(.passed) }
            outcome = .inProgress(step: current)
        } else if current + 1 < steps.count, Self.isDistinctAction(steps[current + 1], s), !Self.isNeutral(s) {
            return finish(.failed(.wrongOrder))                           // did the next step first
        }
        return outcome
    }

    private mutating func finish(_ o: Outcome) -> Outcome { outcome = o; return o }

    static func isNeutral(_ s: Sample) -> Bool { abs(s.yaw) < turnDegrees / 2 && abs(s.pitch) < turnDegrees / 2 && s.eyesOpen > 0.5 }

    static func isDistinctAction(_ step: Step, _ s: Sample) -> Bool {
        switch step {
        case .lookLeft: return s.yaw >= turnDegrees
        case .lookRight: return s.yaw <= -turnDegrees
        case .lookUp: return s.pitch >= turnDegrees
        case .blink: return false   // blinks happen naturally; never count them as "wrong order"
        }
    }

    static func satisfies(_ step: Step, _ s: Sample, eyesWereClosed: inout Bool) -> Bool {
        switch step {
        case .lookLeft, .lookRight, .lookUp:
            return isDistinctAction(step, s)
        case .blink:
            // open → closed → open
            if s.eyesOpen <= blinkClosed { eyesWereClosed = true; return false }
            return eyesWereClosed && s.eyesOpen > 0.5
        }
    }
}

/// Local audit log entry (no images): what happened and why.
public struct FaceUnlockEvent: Codable, Equatable, Sendable {
    public enum Result: String, Codable, Sendable { case unlocked, denied, failed }
    public var at: Date
    public var result: Result
    public var reason: String?
    public var identity: Double?
    public var steps: [LivenessChallenge.Step]
    public init(at: Date, result: Result, reason: String? = nil, identity: Double? = nil, steps: [LivenessChallenge.Step] = []) {
        self.at = at; self.result = result; self.reason = reason; self.identity = identity; self.steps = steps
    }
}

public struct FaceUnlockLog: Codable, Equatable, Sendable {
    public static let limit = 50
    public private(set) var events: [FaceUnlockEvent] = []
    public init() {}

    public mutating func append(_ e: FaceUnlockEvent) {
        events.insert(e, at: 0)
        if events.count > Self.limit { events.removeLast(events.count - Self.limit) }
    }

    /// "Unlocked by face at 14:02 · 2 failed" — failures since the previous successful unlock.
    public var failuresSinceLastUnlock: Int {
        events.prefix { $0.result != .unlocked }.filter { $0.result == .failed }.count
    }
}
