import CoreAudio
import Testing
@testable import DylanCore

@Suite struct AudioMixTests {
    /// Builds an AudioBufferList with `layout` buffers (channels each) of `frames` frames, runs `f`, returns the samples.
    func withList(_ layout: [Int], frames: Int, fill: [[Float]]? = nil, _ f: (UnsafeMutableAudioBufferListPointer) -> Void) -> [[Float]] {
        let list = AudioBufferList.allocate(maximumBuffers: layout.count)
        let buffers = layout.enumerated().map { i, ch -> UnsafeMutablePointer<Float> in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: ch * frames)
            let values = fill?[i] ?? [Float](repeating: 9, count: ch * frames)
            p.initialize(from: values, count: ch * frames)
            list[i] = AudioBuffer(mNumberChannels: UInt32(ch), mDataByteSize: UInt32(ch * frames * 4), mData: p)
            return p
        }
        defer { buffers.forEach { $0.deallocate() }; free(list.unsafeMutablePointer) }
        f(list)
        return layout.indices.map { Array(UnsafeBufferPointer(start: buffers[$0], count: layout[$0] * frames)) }
    }

    let l: [Float] = [1, 2], r: [Float] = [10, 20]

    @Test func stereoInterleaved() {
        let out = withList([2], frames: 2) { AudioMix.render(l, r, frames: 2, gain: 0.5, to: $0) }
        #expect(out == [[0.5, 5, 1, 10]])
    }

    @Test func nonInterleavedAndMultichannel() {
        #expect(withList([1, 1], frames: 2) { AudioMix.render(l, r, frames: 2, gain: 1, to: $0) } == [[1, 2], [10, 20]])
        // HDMI 6 ch: L R L R L R, not silence.
        #expect(withList([6], frames: 1) { AudioMix.render(l, r, frames: 1, gain: 1, to: $0) } == [[1, 10, 1, 10, 1, 10]])
        // Mono output (call mode): the average.
        #expect(withList([1], frames: 2) { AudioMix.render(l, r, frames: 2, gain: 1, to: $0) } == [[5.5, 11]])
    }

    @Test func silenceAndShortInput() {
        #expect(withList([2], frames: 2) { AudioMix.render(l, r, frames: 2, gain: 0, to: $0) } == [[0, 0, 0, 0]])
        #expect(withList([2], frames: 3) { AudioMix.render(l, r, frames: 2, gain: 1, to: $0) } == [[1, 10, 2, 20, 0, 0]])
    }

    @Test func readsTheTapNotTheMic() {
        // A headset mic (1 ch) comes first; the tap is the last buffer (interleaved stereo).
        var left = [Float](repeating: 0, count: 8), right = left
        var frames = 0
        _ = withList([1, 2], frames: 2, fill: [[7, 7], [1, 10, 2, 20]]) { frames = AudioMix.readTap($0, buffers: 1, left: &left, right: &right) }
        #expect(frames == 2 && Array(left.prefix(2)) == [1, 2] && Array(right.prefix(2)) == [10, 20])
        _ = withList([1, 1], frames: 2, fill: [[1, 2], [10, 20]]) { frames = AudioMix.readTap($0, buffers: 2, left: &left, right: &right) }
        #expect(Array(left.prefix(2)) == [1, 2] && Array(right.prefix(2)) == [10, 20])
    }
}
