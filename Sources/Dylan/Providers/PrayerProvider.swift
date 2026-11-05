import AppKit
import AVFoundation
import DylanCore

/// Prayer times (FR-105, FR-106, design D51). The city is picked once and geocoded (no location permission);
/// times are computed on the Mac by the Kemenag method, so everything works offline. A countdown sits in Compact
/// 30 minutes before each prayer, Peek says when it is time, and the adhan (a file the user picks) plays with
/// the music paused and resumed afterwards.
@Observable
final class PrayerProvider {
    static let shared = PrayerProvider()
    enum Adhan: String, CaseIterable { case off, fajr, all }

    private var d: UserDefaults { AppModel.store }
    var city: String { didSet { d.set(city, forKey: "prayer.city") } }
    var latitude: Double? { didSet { d.set(latitude, forKey: "prayer.lat") } }
    var longitude: Double? { didSet { d.set(longitude, forKey: "prayer.lon") } }
    var countdown: Bool { didSet { d.set(countdown, forKey: "prayer.countdown"); refresh() } }
    var showHijri: Bool { didSet { d.set(showHijri, forKey: "prayer.hijri") } }
    var adhan: Adhan { didSet { d.set(adhan.rawValue, forKey: "prayer.adhan") } }
    /// Path of the user's adhan recording; nil plays a short system sound instead.
    var adhanFile: String? { didSet { d.set(adhanFile, forKey: "prayer.adhanFile") } }
    var pauseMusic: Bool { didSet { d.set(pauseMusic, forKey: "prayer.pauseMusic") } }
    /// Minutes before a prayer for a reminder; 0 = off.
    var remindBefore: Int { didSet { d.set(remindBefore, forKey: "prayer.remind") } }
    var ihtiyat: Int { didSet { d.set(ihtiyat, forKey: "prayer.ihtiyat"); refresh() } }

    private(set) var today: PrayerTimes.Day?
    private(set) var next: (prayer: PrayerTimes.Prayer, at: Date)?
    var lookupFailed = false
    private(set) var adhanPlaying = false

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var resumeMusic = false
    @ObservationIgnored private var resumeRadio = false
    @ObservationIgnored private var announced: [String: Date] = [:]
    @ObservationIgnored private let playerDelegate = AdhanDelegate()

    private init() {
        let d = AppModel.store
        city = d.string(forKey: "prayer.city") ?? ""
        latitude = d.object(forKey: "prayer.lat") as? Double
        longitude = d.object(forKey: "prayer.lon") as? Double
        countdown = d.object(forKey: "prayer.countdown") as? Bool ?? true
        showHijri = d.object(forKey: "prayer.hijri") as? Bool ?? true
        adhan = Adhan(rawValue: d.string(forKey: "prayer.adhan") ?? "") ?? .all
        adhanFile = d.string(forKey: "prayer.adhanFile")
        pauseMusic = d.object(forKey: "prayer.pauseMusic") as? Bool ?? true
        remindBefore = d.object(forKey: "prayer.remind") as? Int ?? 10
        ihtiyat = d.object(forKey: "prayer.ihtiyat") as? Int ?? 2
    }

    var hasPlace: Bool { latitude != nil && longitude != nil }

    func start() {
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: 15, repeats: true) { _ in MainActor.assumeIsolated { PrayerProvider.shared.refresh() } }
        t.tolerance = 3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate(); timer = nil
        stopAdhan()
        for id in ["prayer", "prayer-now", "prayer-soon"] { AppModel.shared.removeIfPresent(id, now: Date()) }
    }

    /// Looks the city up (Open-Meteo, the same service as the weather), then recomputes.
    func setCity(_ name: String) {
        city = name.trimmingCharacters(in: .whitespaces)
        latitude = nil; longitude = nil; lookupFailed = false
        refresh()
        guard !city.isEmpty, let url = Weather.geocodeURL(city: city, language: L10n.language) else { return }
        let asked = city
        URLSession.shared.dataTask(with: url) { @Sendable data, _, _ in
            let g = data.flatMap(Weather.parseGeocode)
            Task { @MainActor in
                let p = PrayerProvider.shared
                guard p.city == asked else { return }
                if let g { p.latitude = g.latitude; p.longitude = g.longitude; p.refresh() } else { p.lookupFailed = true }
            }
        }.resume()
    }

    func name(_ p: PrayerTimes.Prayer, on date: Date = Date()) -> String {
        PrayerTimes.isJumuah(p, on: date) ? L("prayer.jumuah") : L("prayer.\(p.rawValue)")
    }

    /// "14.57" (id) / "2:57 PM" (en): the locale's short time, minutes always two digits.
    static func clock(_ d: Date) -> String { d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale)) }

    var hijriToday: String { PrayerTimes.hijri(Date(), locale: L10n.locale) }

    func refresh(now: Date = Date()) {
        guard let lat = latitude, let lon = longitude else {
            today = nil; next = nil
            // The city changed or was not found: no countdown for a place that no longer applies.
            for id in ["prayer", "prayer-soon"] { AppModel.shared.removeIfPresent(id, now: now) }
            return
        }
        let day = PrayerTimes.day(for: now, latitude: lat, longitude: lon, ihtiyat: ihtiyat)
        if day != today { today = day }
        let n = PrayerTimes.next(after: now, latitude: lat, longitude: lon, ihtiyat: ihtiyat)
        if next?.at != n.at { next = n }
        let m = AppModel.shared
        guard m.features.isEnabled(.prayer) else { return }

        // The moment itself: a prayer whose time passed in the last two minutes.
        for p in PrayerTimes.Prayer.allCases where p.isPrayer {
            let at = day.time(p), key = "now-\(at.timeIntervalSince1970)"
            if now >= at, now.timeIntervalSince(at) < 120, announced[key] == nil {
                announced[key] = now
                arrived(p, at: at, now: now)
            }
        }
        // Reminder N minutes before.
        if remindBefore > 0 {
            let key = "soon-\(n.at.timeIntervalSince1970)"
            let left = n.at.timeIntervalSince(now)
            if left <= Double(remindBefore * 60), left > 0, announced[key] == nil {
                announced[key] = now
                m.center.post(Activity(id: "prayer-soon", kind: .prayer, priority: .p1, state: .info, symbol: "moon.stars",
                                       label: name(n.prayer, on: n.at), value: DurationFormat.countdown(left),
                                       detail: L("prayer.soon", name(n.prayer, on: n.at), Int((left / 60).rounded(.up))), startedAt: now), now: now)
            }
        }
        announced = announced.filter { now.timeIntervalSince($0.value) < 86400 }

        // Compact countdown (P3) in the last 30 minutes.
        let left = n.at.timeIntervalSince(now)
        if countdown, left <= 30 * 60, left > 0 {
            var a = Activity(id: "prayer", kind: .prayer, priority: .p3, state: .ambient, symbol: "moon.stars",
                             label: name(n.prayer, on: n.at), value: "−" + DurationFormat.countdown(left),
                             detail: L("prayer.countdown", name(n.prayer, on: n.at), PrayerProvider.clock(n.at)),
                             progress: 1 - left / (30 * 60), startedAt: n.at.addingTimeInterval(-30 * 60))
            if let old = m.center.activities["prayer"] { a.updatedAt = old.updatedAt; if old == a { return } }
            m.center.upsert(a)
        } else {
            m.removeIfPresent("prayer", now: now)
        }
        m.scheduleTick()
    }

    private func arrived(_ p: PrayerTimes.Prayer, at: Date, now: Date) {
        let m = AppModel.shared
        m.removeIfPresent("prayer", now: now)
        m.removeIfPresent("prayer-soon", now: now)
        let plays = adhan == .all || (adhan == .fajr && p == .fajr)
        m.center.post(Activity(id: "prayer-now", kind: .prayer, priority: .p1, state: .info, symbol: "moon.stars.fill",
                               label: name(p, on: at), value: PrayerProvider.clock(at),
                               detail: L("prayer.now", name(p, on: at)) + (plays && pauseMusic && adhanFile != nil && m.media?.isPlaying == true ? " · " + L("prayer.musicPaused") : ""),
                               startedAt: now), now: now)
        if m.notchState == .closed || m.notchState == .compact { m.notchState = .peek; m.autoPeekUntil = now.addingTimeInterval(6) }
        if plays { playAdhan() }
        m.scheduleTick()
    }

    // MARK: Adhan

    func playAdhan() {
        stopAdhan()
        // Without a recording only a short chime plays: the music does not need to stop for it.
        guard let path = adhanFile, let p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) else {
            NSSound(named: "Glass")?.play()
            return
        }
        if pauseMusic {
            if AppModel.shared.media?.isPlaying == true { MediaProvider.shared.playPause(); resumeMusic = true }
            if RadioPlayer.shared.playing { RadioPlayer.shared.pause(); resumeRadio = true }
        }
        p.delegate = playerDelegate
        p.play()
        player = p
        adhanPlaying = true
    }

    func stopAdhan() {
        guard let p = player else { return }
        p.stop()
        finishedAdhan()
    }

    fileprivate func finishedAdhan() {
        player = nil
        adhanPlaying = false
        if resumeMusic { resumeMusic = false; if AppModel.shared.media?.isPlaying == false { MediaProvider.shared.playPause() } }
        if resumeRadio { resumeRadio = false; RadioPlayer.shared.resume() }
    }

    func chooseAdhanFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { adhanFile = url.path }
    }
}

private final class AdhanDelegate: NSObject, AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in PrayerProvider.shared.finishedAdhan() }
    }
}
