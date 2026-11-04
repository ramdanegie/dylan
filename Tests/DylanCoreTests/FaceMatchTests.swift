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
}
