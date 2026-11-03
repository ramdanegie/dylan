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

    /// `processes`: every Core Audio process object of the app (browsers and Electron apps play from helpers).
    init?(pid: pid_t, processes: [AudioObjectID], mode: Mode, onMono: (@Sendable (UnsafeBufferPointer<Float>, Double) -> Void)? = nil) {
        self.pid = pid
        guard !processes.isEmpty, let outputUID = Self.defaultOutputUID() else { return nil }
        let desc = CATapDescription(stereoMixdownOfProcesses: processes)
        desc.uuid = UUID()
        desc.isPrivate = true
        // mutedWhenTapped: silent at the source only while Dylan reads the tap, so a stalled or dead IO never
        // leaves the app muted.
        desc.muteBehavior = mode == .gain ? .mutedWhenTapped : .unmuted
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
        // The tap's stream comes after any input streams of the output device (a headset mic): use the last ones.
        let tapBuffers = Self.tapBufferCount(tapID)
        let gainBox = gain
        let passThrough = mode == .gain
        var left = [Float](repeating: 0, count: 8192), right = [Float](repeating: 0, count: 8192)
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, inInput, _, outOutput, _ in
            let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInput))
            let output = UnsafeMutableAudioBufferListPointer(outOutput)
            let frames = AudioMix.readTap(input, buffers: tapBuffers, left: &left, right: &right)
            AudioMix.render(left, right, frames: frames, gain: passThrough ? gainBox.value : 0, to: output)
            if let onMono, frames > 0 {
                for i in 0..<frames { left[i] = (left[i] + right[i]) / 2 }
                left.withUnsafeBufferPointer { onMono(UnsafeBufferPointer(rebasing: $0[0..<frames]), rate) }
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

    static func tapBufferCount(_ tap: AudioObjectID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var f = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tap, &addr, 0, nil, &size, &f) == noErr else { return 1 }
        return f.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? max(1, Int(f.mChannelsPerFrame)) : 1
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

    /// Every Core Audio process object with its app (browser and Electron helpers mapped to the app).
    @MainActor static func processes() -> [(object: AudioObjectID, app: NSRunningApplication, playing: Bool)] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { p in
            var pa = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = 0
            var ps = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(p, &pa, 0, nil, &ps, &pid) == noErr, pid != getpid(),
                  let app = PrivacyProvider.owningApp(pid: pid, processObject: p) else { return nil }
            var a = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput,
                                               mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var on: UInt32 = 0
            var s = UInt32(MemoryLayout<UInt32>.size)
            let playing = AudioObjectGetPropertyData(p, &a, 0, nil, &s, &on) == noErr && on != 0
            return (p, app, playing)
        }
    }

    /// The process objects of one app, for its tap.
    @MainActor static func processObjects(of pid: pid_t) -> [AudioObjectID] {
        let list = processes().filter { $0.app.processIdentifier == pid }.map(\.object)
        return list.isEmpty ? processObject(pid).map { [$0] } ?? [] : list
    }
}
