import AppKit
import AudioToolbox
import CoreAudio
import DylanCore
import Synchronization

/// One Core Audio process tap (macOS 14.2+) on an app's output, read through a private aggregate device
/// clocked by the default output. Public API only; the tap is private to Dylan and disappears with it, so a
/// crash can never leave an app muted. macOS asks for audio-capture permission on the first tap.
///
/// - observe: the app plays normally; samples go to `onMono` (visualizer, FR-63).
/// - gain: the app is muted at the source and Dylan plays it back × `gain` (volume per app, FR-84).
nonisolated final class AudioTap: @unchecked Sendable {
    enum Mode { case observe, gain }

    let pid: pid_t
    /// Read on the audio thread; a box so the IO block does not retain the tap (deinit must still run).
    final class Gain: Sendable {
        private let bits = Atomic<UInt32>(Float(1).bitPattern)
        var value: Float {
            get { Float(bitPattern: bits.load(ordering: .relaxed)) }
            set { bits.store(newValue.bitPattern, ordering: .relaxed) }
        }
    }
    let gain = Gain()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "dylan.audiotap", qos: .userInteractive)

    init?(pid: pid_t, mode: Mode, onMono: (@Sendable (UnsafeBufferPointer<Float>, Double) -> Void)? = nil) {
        self.pid = pid
        guard let process = Self.processObject(pid), let outputUID = Self.defaultOutputUID() else { return nil }
        let desc = CATapDescription(stereoMixdownOfProcesses: [process])
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = mode == .gain ? .muted : .unmuted
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else { return nil }
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Dylan",
            kAudioAggregateDeviceUIDKey: "dylan-tap-" + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregateID) == noErr else { destroy(); return nil }
        let rate = Self.sampleRate(aggregateID)
        let gainBox = gain
        let passThrough = mode == .gain
        var mono = [Float](repeating: 0, count: 4096)
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, inInput, _, outOutput, _ in
            let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInput))
            let output = UnsafeMutableAudioBufferListPointer(outOutput)
            if passThrough {
                Self.copy(input, to: output, gain: gainBox.value)
            } else {
                for b in output { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }
            }
            if let onMono, let first = input.first, let data = first.mData {
                // Mono mix of the first buffer (interleaved stereo, or channel 1 when non-interleaved).
                let ch = max(1, Int(first.mNumberChannels))
                let frames = min(mono.count, Int(first.mDataByteSize) / MemoryLayout<Float>.size / ch)
                let p = data.assumingMemoryBound(to: Float.self)
                for i in 0..<frames {
                    var s: Float = 0
                    for c in 0..<ch { s += p[i * ch + c] }
                    mono[i] = s / Float(ch)
                }
                mono.withUnsafeBufferPointer { onMono(UnsafeBufferPointer(rebasing: $0[0..<frames]), rate) }
            }
        }
        guard status == noErr, AudioDeviceStart(aggregateID, procID) == noErr else { destroy(); return nil }
    }

    deinit { destroy() }

    func destroy() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            self.procID = nil
        }
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = AudioObjectID(kAudioObjectUnknown) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
    }

    /// Copies matching buffers × gain; zeroes what does not match so nothing is played twice or as noise.
    static func copy(_ input: UnsafeMutableAudioBufferListPointer, to output: UnsafeMutableAudioBufferListPointer, gain: Float) {
        for (i, out) in output.enumerated() {
            guard let od = out.mData else { continue }
            let outCount = Int(out.mDataByteSize) / MemoryLayout<Float>.size
            guard i < input.count, let id = input[i].mData, input[i].mNumberChannels == out.mNumberChannels else {
                memset(od, 0, Int(out.mDataByteSize)); continue
            }
            let n = min(outCount, Int(input[i].mDataByteSize) / MemoryLayout<Float>.size)
            var g = gain
            vDSPScale(id.assumingMemoryBound(to: Float.self), od.assumingMemoryBound(to: Float.self), &g, n)
            if n < outCount { memset(od.advanced(by: n * MemoryLayout<Float>.size), 0, (outCount - n) * MemoryLayout<Float>.size) }
        }
    }

    private static func vDSPScale(_ src: UnsafePointer<Float>, _ dst: UnsafeMutablePointer<Float>, _ g: inout Float, _ n: Int) {
        for i in 0..<n { dst[i] = src[i] * g }
    }

    // MARK: Core Audio lookups

    static func processObject(_ pid: pid_t) -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var p = pid
        var out = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let r = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, UInt32(MemoryLayout<pid_t>.size), &p, &size, &out)
        return r == noErr && out != kAudioObjectUnknown ? out : nil
    }

    static func defaultOutputUID() -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dev = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return nil }
        var uidAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var s = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &uidAddr, 0, nil, &s, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    static func sampleRate(_ device: AudioObjectID) -> Double {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var rate: Float64 = 48_000
        var size = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &rate)
        return rate
    }

    /// Apps currently playing audio (Core Audio process objects), mapped to their app (browser helpers included).
    @MainActor static func playingApps() -> [NSRunningApplication] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        var seen = Set<pid_t>(), apps: [NSRunningApplication] = []
        for p in ids {
            var a = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput,
                                               mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var on: UInt32 = 0
            var s = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(p, &a, 0, nil, &s, &on) == noErr, on != 0 else { continue }
            var pa = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = 0
            var ps = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(p, &pa, 0, nil, &ps, &pid) == noErr, pid != getpid(),
                  let app = PrivacyProvider.owningApp(pid: pid, processObject: p), seen.insert(app.processIdentifier).inserted else { continue }
            apps.append(app)
        }
        return apps
    }
}
