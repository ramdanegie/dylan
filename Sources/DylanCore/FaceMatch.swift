import CoreGraphics
import CryptoKit
import Foundation

/// Identity for Face Unlock (FR-50/51). Vision's image feature print of the aligned face crop (Apple's own
/// model, part of macOS; no third-party face model with an MIT-compatible license exists). Feature prints are
/// generic, so the threshold is learned from the user's own enrollment spread and identity is checked on every
/// frame of a random challenge. Still a convenience feature: weaker than Touch ID or the password.
public struct FaceTemplate: Codable, Equatable, Sendable {
    public var prints: [[Float]]
    public var threshold: Float
    public var createdAt: Date
}

public enum FaceMatcher {
    public static let minimumFrames = 12

    public static func distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        var s: Float = 0
        for i in 0..<a.count { let d = a[i] - b[i]; s += d * d }
        return s.squareRoot()
    }

    /// Threshold = the largest distance between enrolled frames × 1.1: anything farther than the user ever is
    /// from themselves is not them.
    public static func enroll(_ prints: [[Float]], now: Date) -> FaceTemplate? {
        guard prints.count >= minimumFrames, Set(prints.map(\.count)).count == 1 else { return nil }
        var spread: Float = 0
        for i in 0..<prints.count { for j in (i + 1)..<prints.count { spread = max(spread, distance(prints[i], prints[j])) } }
        guard spread > 0, spread.isFinite else { return nil }
        return FaceTemplate(prints: prints, threshold: spread * 1.1, createdAt: now)
    }

    /// 0…1; ≥ 0.66 (LivenessChallenge's bar) exactly when the nearest enrolled frame is within the threshold.
    public static func identity(_ p: [Float], _ t: FaceTemplate) -> Double {
        let nearest = t.prints.map { distance(p, $0) }.min() ?? .infinity
        return Double(max(0, min(1, 1 - 0.34 * nearest / t.threshold)))
    }
}

public enum FaceGeometry {
    /// Eye openness from the eye contour: height over width, mapped so a relaxed open eye ≈ 1 and closed ≈ 0.
    public static func eyeOpenness(_ points: [CGPoint]) -> Double {
        guard points.count >= 4, let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(), maxX > minX else { return 1 }
        let ratio = Double((maxY - minY) / (maxX - minX))
        return max(0, min(1, (ratio - 0.12) / (0.30 - 0.12)))
    }

    /// Same face across frames when the boxes overlap enough; a new face gets a new id.
    public struct Tracker: Sendable {
        private var last: CGRect?
        private var id = 0
        public init() {}
        public mutating func track(_ box: CGRect) -> Int {
            if let l = last, Self.iou(l, box) > 0.3 { last = box; return id }
            id += 1; last = box
            return id
        }
        static func iou(_ a: CGRect, _ b: CGRect) -> Double {
            let i = a.intersection(b)
            guard !i.isNull else { return 0 }
            let inter = Double(i.width * i.height)
            return inter / (Double(a.width * a.height) + Double(b.width * b.height) - inter)
        }
    }
}

/// The enrollment, settings and log on disk, sealed with AES-GCM under a key kept in the Keychain (FR-50:
/// "embedding saja, terenkripsi"). No images are ever stored.
public struct FaceVault: Codable, Equatable, Sendable {
    public var template: FaceTemplate?
    public var settings = FaceUnlockPolicy.Settings()
    public var log = FaceUnlockLog()
    public var consecutiveFailures = 0
    public init() {}

    public func sealed(with key: SymmetricKey) throws -> Data {
        try AES.GCM.seal(JSONEncoder().encode(self), using: key).combined!
    }

    public static func open(_ data: Data, with key: SymmetricKey) throws -> FaceVault {
        try JSONDecoder().decode(FaceVault.self, from: AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key))
    }
}
