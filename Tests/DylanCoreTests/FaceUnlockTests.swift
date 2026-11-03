import Foundation
import Testing
@testable import DylanCore

private let boot = Date(timeIntervalSince1970: 5_000_000)
private let now = boot.addingTimeInterval(3600 * 5)

private func facts(_ change: (inout FaceUnlockPolicy.Facts) -> Void = { _ in }) -> FaceUnlockPolicy.Facts {
    var f = FaceUnlockPolicy.Facts(now: now, screenLocked: true, lockedAt: now.addingTimeInterval(-300), bootTime: boot,
                                   lastPasswordUnlock: boot.addingTimeInterval(60))
    change(&f)
    return f
}

@Suite struct FaceUnlockPolicyTests {
    var policy: FaceUnlockPolicy = {
        var s = FaceUnlockPolicy.Settings(); s.enabled = true
        return FaceUnlockPolicy(settings: s)
    }()

    @Test func allowedInTheNormalCase() { #expect(policy.denial(facts()) == nil) }

    @Test func denials() {
        let cases: [(FaceUnlockPolicy.Denial, (inout FaceUnlockPolicy.Facts) -> Void)] = [
            (.notLocked, { $0.screenLocked = false }),
            (.notEnrolled, { $0.enrolled = false }),
            (.noAccessibility, { $0.accessibilityTrusted = false }),
            (.presentationMode, { $0.presentationMode = true }),
            (.firstUnlockSinceBoot, { $0.lastPasswordUnlock = nil }),
            (.firstUnlockSinceBoot, { $0.lastPasswordUnlock = boot.addingTimeInterval(-10) }),   // before this boot
            (.passwordTooOld, { $0.now = $0.lastPasswordUnlock!.addingTimeInterval(48 * 3600) }),
            (.tooManyFailures, { $0.consecutiveFailures = 5 }),
            (.alreadyTriedThisLock, { $0.passwordTypedThisLock = true }),
            (.lockedTooLong, { $0.lockedAt = now.addingTimeInterval(-3600) }),
            (.lockedTooLong, { $0.lockedAt = nil }),
            (.justLockedManually, { $0.lockWasManual = true; $0.lockedAt = now.addingTimeInterval(-3) }),
        ]
        for (expected, change) in cases { #expect(policy.denial(facts(change)) == expected, "\(expected)") }
    }

    @Test func offByDefaultAndTrustedNetworks() {
        #expect(FaceUnlockPolicy(settings: .init()).denial(facts()) == .disabled)
        var s = policy.settings
        s.trustedNetworksOnly = true; s.trustedNetworks = ["Rumah"]
        let p = FaceUnlockPolicy(settings: s)
        #expect(p.denial(facts { $0.network = "Kafe" }) == .untrustedNetwork)
        #expect(p.denial(facts { $0.network = nil }) == .untrustedNetwork)
        #expect(p.denial(facts { $0.network = "Rumah" }) == nil)
        #expect(policy.denial(facts { $0.lockWasManual = true; $0.lockedAt = now.addingTimeInterval(-30) }) == nil)
    }
}

@Suite struct LivenessTests {
    typealias S = LivenessChallenge.Sample

    @Test func passesWhenFollowingTheSteps() {
        var c = LivenessChallenge(steps: [.lookLeft, .blink])
        #expect(c.feed(S(time: 0.2)) == .inProgress(step: 0))
        #expect(c.feed(S(time: 0.8, yaw: 20)) == .inProgress(step: 1))
        #expect(c.feed(S(time: 1.2, eyesOpen: 0.1)) == .inProgress(step: 1))
        #expect(c.feed(S(time: 1.4, eyesOpen: 0.9)) == .passed)
    }

    @Test func noStepsNeverPasses() {
        var c = LivenessChallenge(steps: [])
        #expect(c.feed(S(time: 0.2)) == .failed(.wrongOrder))
    }

    @Test func aStaticPhotoTimesOut() {
        var c = LivenessChallenge(steps: [.lookRight, .lookUp])
        for t in stride(from: 0.0, through: 6.0, by: 0.25) { _ = c.feed(S(time: t)) }
        #expect(c.feed(S(time: 6.1)) == .failed(.timeout))
    }

    @Test func aReplayDoingTheWrongMoveFails() {
        var c = LivenessChallenge(steps: [.lookLeft, .lookRight])
        #expect(c.feed(S(time: 0.5, yaw: -25)) == .failed(.wrongOrder))
    }

    @Test func identityIsCheckedOnEveryFrame() {
        var c = LivenessChallenge(steps: [.lookLeft, .lookUp])
        _ = c.feed(S(time: 0.3, yaw: 20))
        #expect(c.feed(S(time: 0.6, pitch: 20, identity: 0.4)) == .failed(.wrongPerson))
    }

    @Test func faceSwapOrSecondFaceFails() {
        var a = LivenessChallenge(steps: [.lookLeft, .lookUp])
        _ = a.feed(S(time: 0.3, trackID: 1))
        #expect(a.feed(S(time: 0.5, trackID: 2, yaw: 20)) == .failed(.faceChanged))
        var b = LivenessChallenge(steps: [.lookLeft, .lookUp])
        #expect(b.feed(S(time: 0.3, faceCount: 2)) == .failed(.multipleFaces))
    }

    @Test func naturalBlinksAreNotWrongOrder() {
        var c = LivenessChallenge(steps: [.lookUp, .blink])
        #expect(c.feed(S(time: 0.2, eyesOpen: 0.1)) == .inProgress(step: 0))
        #expect(c.feed(S(time: 0.6, pitch: 20)) == .inProgress(step: 1))
    }

    @Test func randomChallengesHaveTwoDifferentSteps() {
        var g = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let c = LivenessChallenge.random(using: &g)
            #expect(c.steps.count == 2 && c.steps[0] != c.steps[1])
        }
    }

    @Test func auditLogKeepsFiftyAndCountsFailures() {
        var log = FaceUnlockLog()
        log.append(FaceUnlockEvent(at: now, result: .unlocked))
        log.append(FaceUnlockEvent(at: now, result: .failed, reason: "wrongPerson"))
        log.append(FaceUnlockEvent(at: now, result: .denied, reason: "lockedTooLong"))
        log.append(FaceUnlockEvent(at: now, result: .failed, reason: "timeout"))
        #expect(log.failuresSinceLastUnlock == 2)
        for _ in 0..<60 { log.append(FaceUnlockEvent(at: now, result: .denied)) }
        #expect(log.events.count == 50)
    }
}
