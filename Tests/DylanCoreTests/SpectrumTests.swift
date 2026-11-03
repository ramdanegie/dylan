import Foundation
import Testing
@testable import DylanCore

@Suite struct SpectrumTests {
    func sine(_ hz: Double, _ count: Int = 4096, rate: Double = 48_000, amp: Float = 0.5) -> [Float] {
        (0..<count).map { amp * Float(sin(2 * Double.pi * hz * Double($0) / rate)) }
    }

    func levels(_ s: [Float]) -> [Float] {
        let sp = Spectrum()
        var last: [Float] = []
        for chunk in stride(from: 0, to: s.count, by: 512) {
            s[chunk..<min(s.count, chunk + 512)].withUnsafeBufferPointer { if let l = sp.feed($0, sampleRate: 48_000) { last = l } }
        }
        return last
    }

    @Test func bandsFollowFrequency() {
        let bass = levels(sine(100)), treble = levels(sine(6_000)), mid = levels(sine(500))
        #expect(bass.firstIndex(of: bass.max()!) == 0)
        #expect(mid.firstIndex(of: mid.max()!) == 1)
        #expect(treble.firstIndex(of: treble.max()!) == 3)
        #expect(bass[0] > 0.5)
    }

    @Test func silenceIsZeroAndDecays() {
        #expect(levels([Float](repeating: 0, count: 4096)).allSatisfy { $0 < 0.01 })
        let sp = Spectrum()
        let loud = sine(100)
        loud.withUnsafeBufferPointer { _ = sp.feed($0, sampleRate: 48_000) }
        let peak = sp.levels[0]
        [Float](repeating: 0, count: 1024).withUnsafeBufferPointer { _ = sp.feed($0, sampleRate: 48_000) }
        #expect(sp.levels[0] < peak && sp.levels[0] > 0)    // slow decay, not a drop to zero
    }
}
