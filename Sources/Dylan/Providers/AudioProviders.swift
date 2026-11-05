import AppKit
import CoreAudio
import DylanCore

/// Synced lyrics from LRCLIB (FR-62). Opt-in: sends title, artist, album and duration of the song.
@Observable
final class LyricsProvider {
    static let shared = LyricsProvider()
    var lyrics: Lyrics? { didSet { if lyrics != oldValue { lyricsChanged() } } }
    /// Latin transcription per line (D53), made once per song.
    private(set) var romanized: [Int: String] = [:]
    /// Translation per line into the app language (D53), cached per song.
    var translated: [Int: String] = [:]
    @ObservationIgnored private var translations: [String: [Int: String]] = [:]
    var songKey: String? { key }
    @ObservationIgnored private var key: String?
    @ObservationIgnored private var cache: [String: Lyrics?] = [:]
    @ObservationIgnored private var task: URLSessionDataTask?

    func trackChanged(_ m: MediaState?) {
        // Browser tabs and VLC have no reliable artist/duration: LRCLIB would get junk queries.
        guard AppModel.shared.features.isEnabled(.lyrics), let m, m.hasFullControls, !m.title.isEmpty else { lyrics = nil; key = nil; return }
        let k = "\(m.artist)\u{1F}\(m.title)\u{1F}\(Int(m.duration))"
        guard k != key else { return }
        key = k
        if let cached = cache[k] { lyrics = cached; return }
        lyrics = nil
        guard let url = Lyrics.lrclibURL(title: m.title, artist: m.artist, album: m.album, duration: m.duration) else { return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Dylan/0.1 (https://github.com/ramdanegie/dylan)", forHTTPHeaderField: "User-Agent")
        task?.cancel()
        task = URLSession.shared.dataTask(with: req) { @Sendable data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode
            let parsed = status == 200 ? data.flatMap(Lyrics.fromLRCLIB) : nil
            Task { @MainActor in
                let p = LyricsProvider.shared
                // Only a real answer is cached; a cancel, timeout or 5xx tries again next time.
                if status == 200 || status == 404 { p.cache[k] = .some(parsed) }
                if p.key == k { p.lyrics = parsed }
            }
        }
        task?.resume()
    }

    private func lyricsChanged() {
        romanized = [:]
        translated = key.flatMap { translations[$0] } ?? [:]
        guard let lines = lyrics?.lines, lines.contains(where: { Lyrics.needsRomanization($0.text) }) else { return }
        let k = key
        Task.detached {
            var out: [Int: String] = [:]
            for (i, l) in lines.enumerated() { if let r = Lyrics.romanized(l.text) { out[i] = r } }
            await MainActor.run { if LyricsProvider.shared.key == k { LyricsProvider.shared.romanized = out } }
        }
    }

    func storeTranslations(_ t: [Int: String], for k: String) {
        translations[k] = t
        if key == k { translated = t }
    }
}

/// Output devices through Core Audio (FR-61).
@Observable
final class AudioOutputProvider {
    static let shared = AudioOutputProvider()

    struct Device: Identifiable, Equatable {
        var id: AudioObjectID
        var name: String
        var transport: UInt32
        var symbol: String {
            switch transport {
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
                return name.lowercased().contains("airpods") ? "airpodspro" : "headphones"
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
            case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
            case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
            default: return "speaker.wave.2"
            }
        }
    }

    var devices: [Device] = []
    var current: AudioObjectID = 0

    func refresh() {
        devices = Self.outputDevices()
        current = Self.defaultOutput()
    }

    func select(_ d: Device) {
        var id = d.id
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &id)
        refresh()
    }

    var currentName: String? { devices.first { $0.id == current }?.name }

    private static func defaultOutput() -> AudioObjectID {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private static func outputDevices() -> [Device] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            // Output devices have at least one output stream.
            var s = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput,
                                               mElement: kAudioObjectPropertyElementMain)
            var n: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &s, 0, nil, &n) == noErr, n > 0 else { return nil }
            var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                                      mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            var ns = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &ns, &name) == noErr, let cf = name?.takeRetainedValue() else { return nil }
            var tAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
                                                   mElement: kAudioObjectPropertyElementMain)
            var transport: UInt32 = 0
            var ts = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(id, &tAddr, 0, nil, &ts, &transport)
            return Device(id: id, name: cf as String, transport: transport)
        }
    }
}

/// A pinned Spotify playlist/album for quick play (FR-60).
struct QuickPlayItem: Codable, Equatable, Identifiable, Hashable {
    var uri: String
    var name: String
    var id: String { uri }
}
