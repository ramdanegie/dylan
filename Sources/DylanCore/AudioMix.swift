import CoreAudio

/// The process-tap IO for volume per app and the live equalizer (FR-63/84), kept here so it is tested.
/// Runs on the audio thread: no allocation, no locks.
public enum AudioMix {
    /// Stereo frames from the tap's buffers (one interleaved buffer, or one buffer per channel).
    public static func readTap(_ input: UnsafeMutableAudioBufferListPointer, buffers: Int, left: inout [Float], right: inout [Float]) -> Int {
        guard input.count >= buffers, buffers > 0 else { return 0 }
        let tap = Array(input.suffix(buffers))
        if tap.count == 1, let d = tap[0].mData {
            let ch = max(1, Int(tap[0].mNumberChannels))
            let frames = min(left.count, Int(tap[0].mDataByteSize) / MemoryLayout<Float>.size / ch)
            let p = d.assumingMemoryBound(to: Float.self)
            for i in 0..<frames { left[i] = p[i * ch]; right[i] = ch > 1 ? p[i * ch + 1] : p[i * ch] }
            return frames
        }
        guard let l = tap[0].mData else { return 0 }
        let r = tap.count > 1 ? tap[1].mData : nil
        let frames = min(left.count, Int(tap[0].mDataByteSize) / MemoryLayout<Float>.size)
        let lp = l.assumingMemoryBound(to: Float.self), rp = (r ?? l).assumingMemoryBound(to: Float.self)
        for i in 0..<frames { left[i] = lp[i]; right[i] = rp[i] }
        return frames
    }

    /// Writes L/R × gain to every output channel (even = left, odd = right; mono = both), any layout. gain 0 = silence.
    public static func render(_ left: [Float], _ right: [Float], frames: Int, gain: Float, to output: UnsafeMutableAudioBufferListPointer) {
        let total = output.reduce(0) { $0 + Int($1.mNumberChannels) }
        var channel = 0
        for out in output {
            guard let od = out.mData else { continue }
            let ch = max(1, Int(out.mNumberChannels))
            let p = od.assumingMemoryBound(to: Float.self)
            let outFrames = Int(out.mDataByteSize) / MemoryLayout<Float>.size / ch
            for i in 0..<outFrames {
                for c in 0..<ch {
                    let g = channel + c
                    let v: Float = i < frames ? (total == 1 ? (left[i] + right[i]) / 2 : (g % 2 == 0 ? left[i] : right[i])) : 0
                    p[i * ch + c] = v * gain
                }
            }
            channel += ch
        }
    }

}
