import AppKit
import AudioToolbox
import CoreAudio
import DylanCore

/// Volume HUD in the notch (FR-40, design D29). Public API only: a Core Audio listener on the default
/// output's volume and mute. Hiding the system HUD and brightness/backlight need Accessibility and
/// private APIs (spike T2.9), so this is an additional HUD for now.
final class HUDProvider {
    static let shared = HUDProvider()
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var blocks: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var running = false
    private var lastValue: Float?

    func start() {
        guard !running else { return }
        running = true
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { _, _ in
            MainActor.assumeIsolated { HUDProvider.shared.watchDevice() }
        }
        watchDevice()
    }

    func stop() {
        unwatch()
        running = false
    }

    private func unwatch() {
        for (a, b) in blocks { var a = a; AudioObjectRemovePropertyListenerBlock(device, &a, .main, b) }
        blocks = []
    }

    private func watchDevice() {
        unwatch()
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dev = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return }
        device = dev
        lastValue = volume()
        for sel in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(dev, &a) else { continue }
            let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { HUDProvider.shared.changed() } }
            AudioObjectAddPropertyListenerBlock(dev, &a, .main, block)
            blocks.append((a, block))
        }
    }

    private func volume() -> Float? {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                           mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    private func muted() -> Bool {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
                                           mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v) == noErr && v != 0
    }

    private func changed() {
        guard AppModel.shared.features.isEnabled(.hud), let v = volume() else { return }
        let m = muted()
        lastValue = v
        AppModel.shared.showHUD(symbol: m || v == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", value: m ? 0 : Double(v))
    }
}
