import AppKit
import CoreAudio
import CoreWLAN
import DylanCore

/// Extra HUDs (FR-115, design D60). Mic mute (⌃⌥M) mutes the default input device, so every app hears silence,
/// and a red mic stays in the ear while it lasts. "Airplane mode" (⌃⌥⇧A): macOS has none, so Dylan turns Wi‑Fi
/// off and back to how it was. Bluetooth and the keyboard backlight need private APIs and are left out.
@Observable
final class QuickToggles {
    static let shared = QuickToggles()
    private(set) var micMuted = false
    private(set) var airplane = false
    @ObservationIgnored private var mutedDevice: AudioObjectID?
    /// Input volume per element before muting, for devices without a mute switch.
    @ObservationIgnored private var savedVolume: [UInt32: Float32]?
    @ObservationIgnored private var wifiWasOn = false
    @ObservationIgnored private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    /// What Dylan changed, kept on disk so a crash or force quit cannot leave the mic silent for good.
    private struct Muted: Codable { var uid: String; var volumes: [UInt32: Float32]? }
    private static let key = "quick.micMuted"

    // MARK: Microphone

    func toggleMic() { micMuted ? unmuteMic() : muteMic() }

    func muteMic() {
        guard let dev = Self.defaultInput() else { return failed(L("quick.noMic")) }
        guard mute(dev) else { return failed(L("quick.micFailed")) }
        micMuted = true
        watch()
        AppModel.shared.showHUD(symbol: "mic.slash.fill", value: 0, text: L("quick.micOff"))
    }

    func unmuteMic() {
        unwatch()
        release()
        micMuted = false
        AppModel.shared.showHUD(symbol: "mic.fill", value: 1, text: L("quick.micOn"))
    }

    /// At launch: give back the mic a previous run muted and could not restore (crash, force quit).
    func recoverAtLaunch() {
        guard let data = AppModel.store.data(forKey: Self.key), let m = try? JSONDecoder().decode(Muted.self, from: data) else { return }
        AppModel.store.removeObject(forKey: Self.key)
        guard let dev = Self.device(uid: m.uid) else { return }
        if let v = m.volumes { for (el, x) in v { _ = Self.setVolume(dev, el, x) } } else { _ = Self.setMute(dev, false) }
    }

    private func mute(_ dev: AudioObjectID) -> Bool {
        if Self.setMute(dev, true) {
            savedVolume = nil
        } else {
            // A level of 0 is not worth restoring: it would leave the mic silent after "unmute".
            let saved = Self.volumes(dev).mapValues { $0 < 0.05 ? 0.75 : $0 }
            guard !saved.isEmpty, saved.keys.allSatisfy({ Self.setVolume(dev, $0, 0) }) else { return false }
            savedVolume = saved
        }
        mutedDevice = dev
        if let uid = Self.uid(dev), let data = try? JSONEncoder().encode(Muted(uid: uid, volumes: savedVolume)) {
            AppModel.store.set(data, forKey: Self.key)
        }
        return true
    }

    private func release() {
        if let dev = mutedDevice {
            if let saved = savedVolume { for (el, v) in saved { _ = Self.setVolume(dev, el, v) } } else { _ = Self.setMute(dev, false) }
        }
        mutedDevice = nil; savedVolume = nil
        AppModel.store.removeObject(forKey: Self.key)
    }

    /// While muted: a new default mic (AirPods connect) is muted too, and an app that raises the level again
    /// (Zoom, Chrome) is put back to silence.
    private func watch() {
        unwatch()
        var def = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
        listen(AudioObjectID(kAudioObjectSystemObject), &def) { QuickToggles.shared.inputChanged() }
        guard let dev = mutedDevice else { return }
        if let saved = savedVolume {
            for el in saved.keys {
                var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeInput, mElement: el)
                listen(dev, &a) { QuickToggles.shared.enforce() }
            }
        } else {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            listen(dev, &a) { QuickToggles.shared.enforce() }
        }
    }

    private func listen(_ obj: AudioObjectID, _ a: inout AudioObjectPropertyAddress, _ f: @escaping @MainActor () -> Void) {
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { f() } }
        if AudioObjectAddPropertyListenerBlock(obj, &a, .main, block) == noErr { listeners.append((obj, a, block)) }
    }

    private func unwatch() {
        for (obj, a, b) in listeners { var a = a; AudioObjectRemovePropertyListenerBlock(obj, &a, .main, b) }
        listeners = []
    }

    private func inputChanged() {
        guard micMuted, let new = Self.defaultInput(), new != mutedDevice else { return }
        release()
        if mute(new) { watch() } else { unwatch(); micMuted = false; failed(L("quick.micFailed")) }
    }

    private func enforce() {
        guard micMuted, let dev = mutedDevice else { return }
        if let saved = savedVolume {
            for el in saved.keys where (Self.volume(dev, el) ?? 0) > 0.001 { _ = Self.setVolume(dev, el, 0) }
        } else if !Self.isMuted(dev) {
            _ = Self.setMute(dev, true)
        }
    }

    // MARK: Airplane (Wi‑Fi only)

    func toggleAirplane() {
        guard let wifi = CWWiFiClient.shared().interface() else { return failed(L("quick.noWifi")) }
        do {
            if airplane {
                if wifiWasOn { try wifi.setPower(true) }
                airplane = false
                AppModel.shared.showHUD(symbol: "airplane", value: 0, text: L("quick.airplaneOff"))
            } else {
                wifiWasOn = wifi.powerOn()
                try wifi.setPower(false)
                airplane = true
                AppModel.shared.showHUD(symbol: "airplane", value: 1, text: L("quick.airplaneOn"))
            }
        } catch {
            failed(error.localizedDescription)
        }
    }

    /// Leave the Mac as it was found when Dylan quits or the feature is turned off.
    func restore() {
        if micMuted { unmuteMic() }
        if airplane { toggleAirplane() }
    }

    private func failed(_ message: String) {
        let now = Date()
        AppModel.shared.center.post(Activity(id: "quick-failed", kind: .notify, priority: .p2, state: .failure, symbol: "exclamationmark.triangle",
                                             label: L("quick.title"), detail: message, startedAt: now), now: now)
        AppModel.shared.scheduleTick()
    }

    // MARK: Core Audio

    private static func defaultInput() -> AudioObjectID? {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var dev = AudioObjectID(0), size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev) == noErr, dev != 0 else { return nil }
        return dev
    }

    private static func uid(_ dev: AudioObjectID) -> String? {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr, let s = v?.takeRetainedValue() else { return nil }
        return s as String
    }

    private static func device(uid: String) -> AudioObjectID? {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var cf = uid as CFString
        var dev = AudioObjectID(0), size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &cf) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, UInt32(MemoryLayout<CFString>.size), $0, &size, &dev)
        }
        return status == noErr && dev != 0 ? dev : nil
    }

    private static func isMuted(_ dev: AudioObjectID) -> Bool {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr && v != 0
    }

    private static func volume(_ dev: AudioObjectID, _ element: UInt32) -> Float32? {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeInput, mElement: element)
        var v: Float32 = 0, size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    private static func setMute(_ dev: AudioObjectID, _ on: Bool) -> Bool {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(dev, &a), AudioObjectIsPropertySettable(dev, &a, &settable) == noErr, settable.boolValue else { return false }
        var v: UInt32 = on ? 1 : 0
        return AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }

    /// Settable input volumes: the main element, or each channel when the device has no main one (built-in mics).
    private static func volumes(_ dev: AudioObjectID) -> [UInt32: Float32] {
        var out: [UInt32: Float32] = [:]
        for el in [kAudioObjectPropertyElementMain, 1, 2] {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeInput, mElement: el)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(dev, &a), AudioObjectIsPropertySettable(dev, &a, &settable) == noErr, settable.boolValue else { continue }
            var v: Float32 = 0, size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr { out[el] = v }
            if el == kAudioObjectPropertyElementMain && !out.isEmpty { break }
        }
        return out
    }

    private static func setVolume(_ dev: AudioObjectID, _ element: UInt32, _ value: Float32) -> Bool {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeInput, mElement: element)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(dev, &a), AudioObjectIsPropertySettable(dev, &a, &settable) == noErr, settable.boolValue else { return false }
        var v = value
        return AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }
}
