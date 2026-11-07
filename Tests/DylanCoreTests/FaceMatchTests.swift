import CoreGraphics
import CryptoKit
import Foundation
import Testing
@testable import DylanCore

@Suite struct FaceMatchTests {
    func noisy(_ base: [Float], _ amp: Float, _ seed: Int) -> [Float] {
        base.enumerated().map { i, v in v + amp * Float(sin(Double(i * 31 + seed * 17))) }
    }

    @Test func enrollAndIdentify() throws {
        let me = (0..<64).map { Float(sin(Double($0))) }
        let other = (0..<64).map { Float(cos(Double($0) * 1.7)) }
        let prints = (0..<15).map { noisy(me, 0.05, $0) }
        let t = try #require(FaceMatcher.enroll(prints, now: Date()))
        #expect(FaceMatcher.identity(noisy(me, 0.04, 99), t) >= 0.66)
        #expect(FaceMatcher.identity(other, t) < 0.66)
        #expect(FaceMatcher.enroll(Array(prints.prefix(5)), now: Date()) == nil)        // too few frames
        #expect(FaceMatcher.enroll(Array(repeating: me, count: 15), now: Date()) == nil) // no spread: a photo
    }

    @Test func guidedEnrollmentIsTighterThanTheWidestSpread() throws {
        let me = (0..<64).map { Float(sin(Double($0))) }
        // Nine directions, two frames each; each direction drifts further from straight ahead.
        var prints: [[Float]] = [], poses: [Int] = []
        for pose in 0..<9 { for k in 0..<2 { prints.append(noisy(me, 0.02 + Float(pose) * 0.03, pose * 10 + k)); poses.append(pose) } }
        let loose = try #require(FaceMatcher.enroll(prints, now: Date()))
        let guided = try #require(FaceMatcher.enroll(prints, poses: poses, now: Date()))
        #expect(guided.threshold < loose.threshold)
        #expect(FaceMatcher.identity(noisy(me, 0.02, 500), guided) >= 0.66)
    }

    @Test func onlyEnabledIdentitiesMatch() throws {
        let me = (0..<64).map { Float(sin(Double($0))) }
        let other = (0..<64).map { Float(cos(Double($0) * 1.7)) }
        let mine = try #require(FaceMatcher.enroll((0..<15).map { noisy(me, 0.05, $0) }, now: Date()))
        let theirs = try #require(FaceMatcher.enroll((0..<15).map { noisy(other, 0.05, $0) }, now: Date()))
        var ids = [FaceIdentity(name: "", template: mine), FaceIdentity(name: "Kacamata", template: theirs)]
        #expect(FaceMatcher.identity(noisy(other, 0.04, 7), ids) >= 0.66)
        ids[1].enabled = false
        #expect(FaceMatcher.identity(noisy(other, 0.04, 7), ids) < 0.66)
        #expect(FaceMatcher.identity(me, []) == 0)
    }

    @Test func poseCoverage() {
        var signs = PoseSigns()
        #expect(PoseCoverage.classify(yaw: 0, pitch: 0, signs: &signs, asking: .center) == .pose(.center))
        #expect(PoseCoverage.classify(yaw: 6, pitch: -7, signs: &signs, asking: .center) == .pose(.center))
        #expect(PoseCoverage.classify(yaw: -40, pitch: 0, signs: &signs, asking: .left) == .tooFar)
        // A turn before the wizard asked for one cannot be named yet.
        #expect(PoseCoverage.classify(yaw: -14, pitch: 0, signs: &signs, asking: .center) == .unknown)
        // Asked for "left", the user turns and Vision says −14: that sign is "left" from now on.
        #expect(PoseCoverage.classify(yaw: -14, pitch: 0, signs: &signs, asking: .left) == .pose(.left))
        #expect(signs.yaw == -1)
        #expect(PoseCoverage.classify(yaw: 18, pitch: 3, signs: &signs, asking: .right) == .pose(.right))
        #expect(PoseCoverage.classify(yaw: 3, pitch: 12, signs: &signs, asking: .right) == .unknown)   // pitch not learned yet
        #expect(PoseCoverage.classify(yaw: 3, pitch: 12, signs: &signs, asking: .up) == .pose(.up))
        #expect(signs.pitch == 1)
        #expect(PoseCoverage.classify(yaw: -12, pitch: -18, signs: &signs, asking: .down) == .pose(.down))   // diagonal: larger axis
        #expect(signs.apply(yaw: -14, pitch: 12) == (14, 12))
        #expect(PoseSigns().apply(yaw: 10, pitch: 10) == (-10, -10))
        var c = PoseCoverage()
        #expect(c.add(.center) && c.add(.center) && c.add(.center) && !c.add(.center))
        #expect(c.missing == .left && c.done == 3 && !c.complete)
        for p in PoseCoverage.Pose.allCases { for _ in 0..<3 { _ = c.add(p) } }
        #expect(c.complete && c.missing == nil && c.done == PoseCoverage.total && PoseCoverage.total >= FaceMatcher.minimumFrames)
    }

    @Test func deviceAroundTheFace() {
        let face = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        #expect(FaceGeometry.framedByDevice(face: face, rects: [CGRect(x: 0.35, y: 0.32, width: 0.3, height: 0.42)]))   // a phone held up
        #expect(!FaceGeometry.framedByDevice(face: face, rects: [CGRect(x: 0, y: 0, width: 1, height: 1)]))            // a door behind you
        #expect(!FaceGeometry.framedByDevice(face: face, rects: [CGRect(x: 0.38, y: 0.1, width: 0.3, height: 0.55)]))  // off-centre frame
        #expect(!FaceGeometry.framedByDevice(face: face, rects: [CGRect(x: 0.5, y: 0.3, width: 0.3, height: 0.45)]))   // beside the face
        #expect(!FaceGeometry.framedByDevice(face: face, rects: []))
    }

    @Test func eyesAndTracking() {
        let open = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0.3), CGPoint(x: 2, y: 0), CGPoint(x: 1, y: -0.3)]       // h/w 0.3
        let half = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0.21), CGPoint(x: 2, y: 0), CGPoint(x: 1, y: -0.21)]     // h/w 0.21
        let closed = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0.02), CGPoint(x: 2, y: 0), CGPoint(x: 1, y: -0.02)]
        #expect(FaceGeometry.eyeOpenness(open) == 1)
        #expect(abs(FaceGeometry.eyeOpenness(half) - 0.5) < 0.01)
        #expect(FaceGeometry.eyeOpenness(closed) == 0)
        var tr = FaceGeometry.Tracker()
        let a = tr.track(CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3))
        #expect(tr.track(CGRect(x: 0.32, y: 0.31, width: 0.3, height: 0.3)) == a)
        #expect(tr.track(CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2)) != a)
    }

    @Test func vaultIsSealed() throws {
        var v = FaceVault()
        v.settings.enabled = true
        v.consecutiveFailures = 2
        let key = SymmetricKey(size: .bits256)
        var data = try v.sealed(with: key)
        #expect(try FaceVault.open(data, with: key) == v)
        #expect(!String(decoding: data, as: UTF8.self).contains("enabled"))
        #expect(throws: (any Error).self) { try FaceVault.open(data, with: SymmetricKey(size: .bits256)) }
        data[data.count / 2] ^= 0xFF
        #expect(throws: (any Error).self) { try FaceVault.open(data, with: key) }   // tampering is detected
    }

    @Test func vaultFromBeforeLastPasswordUnlockStillOpens() throws {
        // A vault sealed by an older build has no "lastPasswordUnlock" key.
        let key = SymmetricKey(size: .bits256)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(FaceVault())) as! [String: Any]
        old.removeValue(forKey: "lastPasswordUnlock")
        let sealed = try AES.GCM.seal(JSONSerialization.data(withJSONObject: old), using: key).combined!
        let v = try FaceVault.open(sealed, with: key)
        #expect(v.lastPasswordUnlock == nil)
        var w = v
        w.lastPasswordUnlock = Date(timeIntervalSince1970: 1_000)
        #expect(try FaceVault.open(w.sealed(with: key), with: key).lastPasswordUnlock == w.lastPasswordUnlock)
    }

    @Test func vaultWithOneTemplateBecomesOneIdentity() throws {
        // Up to 0.2.x: a single "template" and settings without the lock-screen keys.
        let key = SymmetricKey(size: .bits256)
        let t = FaceTemplate(prints: [[1, 2], [2, 3]], threshold: 1.5, createdAt: Date(timeIntervalSince1970: 0))
        let old: [String: Any] = [
            "template": try JSONSerialization.jsonObject(with: JSONEncoder().encode(t)),
            "settings": ["enabled": true, "maxLockedMinutes": 30, "trustedNetworksOnly": false, "trustedNetworks": [String]()],
            "log": ["events": [Any]()], "consecutiveFailures": 1,
        ]
        let v = try FaceVault.open(AES.GCM.seal(JSONSerialization.data(withJSONObject: old), using: key).combined!, with: key)
        #expect(v.identities.count == 1 && v.identities[0].template == t && v.identities[0].enabled && v.canMatch)
        #expect(v.settings.enabled && v.settings.maxLockedMinutes == 30 && v.settings.speak && !v.settings.spaceRetry)
        #expect(v.consecutiveFailures == 1)
        #expect(try FaceVault.open(v.sealed(with: key), with: key) == v)
    }
}
