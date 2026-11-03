import Accelerate
import Foundation

/// Four equalizer bands from real audio (FR-63): FFT of the latest 1024 samples, energy per band in dB,
/// mapped to 0…1, with fast attack and slow decay so bars move like a meter. Not Sendable: one per audio queue.
public final class Spectrum {
    public static let size = 1024
    /// Band edges in Hz: bass, low-mid, high-mid, treble.
    public static let edges: [Double] = [30, 250, 1_000, 4_000, 16_000]
    public static let floorDB: Float = -70

    private let log2n = vDSP_Length(10)
    private let setup: FFTSetup
    private var window = [Float](repeating: 0, count: Spectrum.size)
    private var ring = [Float](repeating: 0, count: Spectrum.size)
    private var filled = 0
    private(set) public var levels = [Float](repeating: 0, count: 4)

    public init() {
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        vDSP_hann_window(&window, vDSP_Length(Self.size), Int32(vDSP_HANN_NORM))
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Feeds mono samples; returns smoothed levels once a full window is available.
    @discardableResult
    public func feed(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double) -> [Float]? {
        let n = Self.size
        guard sampleRate.isFinite, sampleRate > 0 else { return nil }
        // Keep the newest n samples.
        if samples.count >= n {
            ring = Array(samples.suffix(n)); filled = n
        } else {
            ring.removeFirst(samples.count); ring.append(contentsOf: samples); filled = min(n, filled + samples.count)
        }
        guard filled == n else { return nil }
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(ring, 1, window, 1, &windowed, 1, vDSP_Length(n))
        var real = [Float](repeating: 0, count: n / 2), imag = [Float](repeating: 0, count: n / 2)
        var power = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { r in
            imag.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                windowed.withUnsafeBufferPointer {
                    $0.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2)) }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(n / 2))
            }
        }
        let binHz = sampleRate / Double(n)
        var out = [Float](repeating: 0, count: 4)
        for b in 0..<4 {
            // At low rates (8 kHz call audio) the upper bands lie above Nyquist: leave them at 0.
            let lo = max(1, Int(Self.edges[b] / binHz)), hi = min(n / 2, Int(Self.edges[b + 1] / binHz))
            guard hi > lo else { continue }
            var sum: Float = 0
            vDSP_sve(Array(power[lo..<hi]), 1, &sum, vDSP_Length(hi - lo))
            // Normalised by window and FFT size; 0 dB ≈ a full-scale sine in the band.
            let db = 10 * log10(max(sum / Float(n * n) * 4, 1e-12))
            out[b] = max(0, min(1, (db - Self.floorDB) / -Self.floorDB))
        }
        for b in 0..<4 { levels[b] = out[b] > levels[b] ? levels[b] + (out[b] - levels[b]) * 0.6 : levels[b] * 0.85 + out[b] * 0.15 }
        return levels
    }
}
