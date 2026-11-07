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
    /// from themselves is not them. With guided enrollment (`poses`, one per print) the reach is the widest gap
    /// between one head direction and its nearest other direction instead: the gap between your left and right
    /// profile is large enough to let in someone else looking straight ahead.
    public static func enroll(_ prints: [[Float]], poses: [Int]? = nil, now: Date) -> FaceTemplate? {
        guard prints.count >= minimumFrames, Set(prints.map(\.count)).count == 1 else { return nil }
        var spread: Float = 0
        for i in 0..<prints.count { for j in (i + 1)..<prints.count { spread = max(spread, distance(prints[i], prints[j])) } }
        guard spread > 0, spread.isFinite else { return nil }
        var reach = spread
        if let poses, poses.count == prints.count, Set(poses).count > 1 {
            reach = prints.indices.map { i in
                prints.indices.filter { poses[$0] != poses[i] }.map { distance(prints[i], prints[$0]) }.min() ?? spread
            }.max() ?? spread
            guard reach > 0 else { return nil }
        }
        return FaceTemplate(prints: prints, threshold: reach * 1.1, createdAt: now)
    }

    /// 0…1; ≥ 0.66 (LivenessChallenge's bar) exactly when the nearest enrolled frame is within the threshold.
    public static func identity(_ p: [Float], _ t: FaceTemplate) -> Double {
        let nearest = t.prints.map { distance(p, $0) }.min() ?? .infinity
        return Double(max(0, min(1, 1 - 0.34 * nearest / t.threshold)))
    }

    /// Best score over the identities that are switched on.
    public static func identity(_ p: [Float], _ ids: [FaceIdentity]) -> Double {
        ids.filter(\.enabled).map { identity(p, $0.template) }.max() ?? 0
    }
}

/// One enrolled look (after Glance's "identities"): plain, with glasses, a mask, in dim light, or another person
/// you trust. Each can be switched off without being deleted; only the ones switched on are matched.
public struct FaceIdentity: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// Empty for the first enrollment and for vaults from before identities; the app shows "Main face".
    public var name: String
    public var template: FaceTemplate
    public var enabled: Bool
    public init(id: UUID = UUID(), name: String, template: FaceTemplate, enabled: Bool = true) {
        self.id = id; self.name = name; self.template = template; self.enabled = enabled
    }
}

/// Which way Vision's yaw and pitch point for this Mac's camera: +1 when Vision's value grows as the user turns to
/// their left (yaw) or looks up (pitch). Learned during enrollment (`PoseCoverage.classify`), kept in the vault.
public struct PoseSigns: Codable, Equatable, Sendable {
    public var yaw: Double?
    public var pitch: Double?
    public init(yaw: Double? = nil, pitch: Double? = nil) { self.yaw = yaw; self.pitch = pitch }

    /// Before an enrollment has taught them: Vision's right-handed axes on a mirrored image (+yaw = the user's
    /// right, +pitch = down), hence −1 for both.
    public func apply(yaw: Double, pitch: Double) -> (yaw: Double, pitch: Double) { (yaw * (self.yaw ?? -1), pitch * (self.pitch ?? -1)) }
}

/// Guided enrollment: frames are sorted by head direction and each of the five directions needs `perPose` of
/// them, so the template covers the angles the challenge later asks for. Glance asks for nine; the diagonals were
/// tiring to hit and add little, so Dylan asks for straight ahead, left, right, up and down.
public struct PoseCoverage: Equatable, Sendable {
    public enum Pose: Int, CaseIterable, Sendable {
        case center, left, right, up, down
    }

    public static let perPose = 3
    public static var total: Int { Pose.allCases.count * perPose }
    /// Degrees away from where the head started (the camera's first frame) that count as a direction.
    public static let side = 10.0
    /// Farther than this the face print gets poor: the wizard says "come back a little".
    public static let tooFar = 32.0

    public private(set) var counts: [Pose: Int] = [:]
    public init() {}

    public enum Reading: Equatable, Sendable { case pose(Pose), tooFar, unknown }

    /// A frame's head movement (degrees from where the head started, Vision's own signs) as a direction. Apple does
    /// not document which way Vision's yaw and pitch point, so the signs are learned from the user: the first clear
    /// turn while the wizard asks for "left" (or "up") sets that axis. Until then a turn on that axis is `unknown`.
    /// A diagonal counts for its larger axis.
    public static func classify(yaw: Double, pitch: Double, signs: inout PoseSigns, asking: Pose?) -> Reading {
        if abs(yaw) > tooFar || abs(pitch) > tooFar { return .tooFar }
        if max(abs(yaw), abs(pitch)) < side { return .pose(.center) }
        if abs(yaw) >= abs(pitch) {
            if signs.yaw == nil, asking == .left || asking == .right { signs.yaw = (yaw > 0) == (asking == .left) ? 1 : -1 }
            guard let s = signs.yaw else { return .unknown }
            return .pose(yaw * s > 0 ? .left : .right)
        }
        if signs.pitch == nil, asking == .up || asking == .down { signs.pitch = (pitch > 0) == (asking == .up) ? 1 : -1 }
        guard let s = signs.pitch else { return .unknown }
        return .pose(pitch * s > 0 ? .up : .down)
    }

    /// Keeps the frame only when its direction still needs one.
    public mutating func add(_ p: Pose) -> Bool {
        guard counts[p, default: 0] < Self.perPose else { return false }
        counts[p, default: 0] += 1
        return true
    }

    public func isFull(_ p: Pose) -> Bool { counts[p, default: 0] >= Self.perPose }
    public var done: Int { counts.values.reduce(0) { $0 + min($1, Self.perPose) } }
    public var complete: Bool { done == Self.total }
    /// The direction to ask for next.
    public var missing: Pose? { Pose.allCases.first { !isFull($0) } }
}

public enum FaceGeometry {
    /// Eye openness from the eye contour: height over width, mapped so a relaxed open eye ≈ 1 and closed ≈ 0.
    public static func eyeOpenness(_ points: [CGPoint]) -> Double {
        guard points.count >= 4, let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(), maxX > minX else { return 1 }
        let ratio = Double((maxY - minY) / (maxX - minX))
        return max(0, min(1, (ratio - 0.12) / (0.30 - 0.12)))
    }

    /// A phone or tablet held up to the camera (Glance's "device bezel" cue): a rectangle that frames the face
    /// snugly and around its middle, as a screen showing a face does. A door, window or monitor behind you is larger
    /// and off-centre (a real face fired the first, looser version), so only snug, centred frames count.
    public static func framedByDevice(face: CGRect, rects: [CGRect]) -> Bool {
        let area = face.width * face.height
        guard area > 0 else { return false }
        return rects.contains { r in
            r.insetBy(dx: -face.width * 0.05, dy: -face.height * 0.05).contains(face) && (1.3...4).contains(r.width * r.height / area)
                && abs(r.midX - face.midX) <= r.width * 0.2 && abs(r.midY - face.midY) <= r.height * 0.25
        }
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
    public static let maxIdentities = 5
    public var identities: [FaceIdentity] = []
    public var settings = FaceUnlockPolicy.Settings()
    public var log = FaceUnlockLog()
    public var consecutiveFailures = 0
    /// Last unlock Dylan saw that was not by face (or a verified enrollment). Kept across Dylan restarts;
    /// the policy only counts it when it is after the Mac's boot time.
    public var lastPasswordUnlock: Date?
    public var poseSigns = PoseSigns()
    public init() {}

    /// At least one identity is switched on.
    public var canMatch: Bool { identities.contains(where: \.enabled) }

    private enum CodingKeys: String, CodingKey { case identities, template, settings, log, consecutiveFailures, lastPasswordUnlock, poseSigns }

    /// Every key is optional, so a vault sealed by an older Dylan still opens: losing it would silently drop the
    /// enrollment. Up to 0.2.x the vault held a single `template`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identities = try c.decodeIfPresent([FaceIdentity].self, forKey: .identities) ?? []
        if identities.isEmpty, let t = try c.decodeIfPresent(FaceTemplate.self, forKey: .template) {
            identities = [FaceIdentity(name: "", template: t)]
        }
        settings = try c.decodeIfPresent(FaceUnlockPolicy.Settings.self, forKey: .settings) ?? .init()
        log = try c.decodeIfPresent(FaceUnlockLog.self, forKey: .log) ?? .init()
        consecutiveFailures = try c.decodeIfPresent(Int.self, forKey: .consecutiveFailures) ?? 0
        lastPasswordUnlock = try c.decodeIfPresent(Date.self, forKey: .lastPasswordUnlock)
        poseSigns = try c.decodeIfPresent(PoseSigns.self, forKey: .poseSigns) ?? .init()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(identities, forKey: .identities)
        // 0.2.x reads only this; without it, going back would show no enrollment and overwrite the vault.
        try c.encodeIfPresent(identities.first?.template, forKey: .template)
        try c.encode(settings, forKey: .settings)
        try c.encode(log, forKey: .log)
        try c.encode(consecutiveFailures, forKey: .consecutiveFailures)
        try c.encodeIfPresent(lastPasswordUnlock, forKey: .lastPasswordUnlock)
        try c.encode(poseSigns, forKey: .poseSigns)
    }

    public func sealed(with key: SymmetricKey) throws -> Data {
        try AES.GCM.seal(JSONEncoder().encode(self), using: key).combined!
    }

    public static func open(_ data: Data, with key: SymmetricKey) throws -> FaceVault {
        try JSONDecoder().decode(FaceVault.self, from: AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key))
    }
}
