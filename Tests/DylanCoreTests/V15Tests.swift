import Foundation
import Testing
@testable import DylanCore

/// Logic behind the v1.5 design (D51–D60).
@Suite struct V15Tests {
    let jakarta = TimeZone(identifier: "Asia/Jakarta")!

    private func hm(_ d: Date, _ tz: TimeZone) -> Int {
        var c = Calendar(identifier: .gregorian); c.timeZone = tz
        let x = c.dateComponents([.hour, .minute], from: d)
        return x.hour! * 60 + x.minute!
    }

    /// Kemenag's schedule for DKI Jakarta in early November (± 3 minutes for city-centre coordinates and year).
    @Test func prayerTimesJakarta() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = jakarta
        let date = c.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9))!
        let d = PrayerTimes.day(for: date, latitude: -6.2088, longitude: 106.8456, timeZone: jakarta)
        let expected: [(PrayerTimes.Prayer, Int)] = [(.fajr, 4 * 60 + 7), (.sunrise, 5 * 60 + 22), (.dhuhr, 11 * 60 + 39),
                                                    (.asr, 14 * 60 + 57), (.maghrib, 17 * 60 + 51), (.isha, 19 * 60 + 4)]
        for (p, m) in expected {
            #expect(abs(hm(d.time(p), jakarta) - m) <= 3, "\(p): \(hm(d.time(p), jakarta) / 60):\(hm(d.time(p), jakarta) % 60)")
        }
        // Whole minutes, in order.
        let order = PrayerTimes.Prayer.allCases.map { d.time($0) }
        #expect(order == order.sorted())
        #expect(order.allSatisfy { Int($0.timeIntervalSince1970) % 60 == 0 })
    }

    @Test func nextPrayerRollsOverMidnight() {
        var c = Calendar(identifier: .gregorian); c.timeZone = jakarta
        let late = c.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 22))!
        let n = PrayerTimes.next(after: late, latitude: -6.2, longitude: 106.85, timeZone: jakarta)
        #expect(n.prayer == .fajr)
        #expect(c.component(.day, from: n.at) == 6)
        let noon = c.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 12, minute: 30))!   // a Friday
        let m = PrayerTimes.next(after: noon, latitude: -6.2, longitude: 106.85, timeZone: jakarta)
        #expect(m.prayer == .asr)
        #expect(PrayerTimes.isJumuah(.dhuhr, on: noon, timeZone: jakarta))
        #expect(!PrayerTimes.isJumuah(.asr, on: noon, timeZone: jakarta))
    }

    @Test func ihtiyatShiftsPrayersNotSunrise() {
        let date = Date(timeIntervalSince1970: 1_793_900_000)
        let a = PrayerTimes.day(for: date, latitude: -6.2, longitude: 106.85, timeZone: jakarta, ihtiyat: 0)
        let b = PrayerTimes.day(for: date, latitude: -6.2, longitude: 106.85, timeZone: jakarta, ihtiyat: 4)
        #expect(b.time(.asr).timeIntervalSince(a.time(.asr)) >= 180)
        #expect(b.time(.sunrise) < a.time(.sunrise))
    }

    @Test func pomodoroAutoStart() {
        let t0 = Date(timeIntervalSince1970: 0)
        var cfg = PomodoroConfig()
        cfg.focus = 50 * 60; cfg.shortBreak = 10 * 60
        let focus = CountdownTimer.pomodoro(now: t0, config: cfg)
        #expect(focus.duration == 3000)
        let rest = focus.next(now: t0, config: cfg)!
        #expect(rest.phase == .shortBreak && !rest.isPaused && rest.duration == 600)
        // The next focus waits for the user by default…
        let back = rest.next(now: t0, config: cfg)!
        #expect(back.phase == .focus && back.isPaused && back.remaining(now: t0.addingTimeInterval(999)) == 3000)
        // …and starts by itself when asked to.
        cfg.autoFocus = true
        #expect(rest.next(now: t0, config: cfg)!.isPaused == false)
        cfg.autoBreak = false
        #expect(focus.next(now: t0, config: cfg)!.isPaused)
    }

    @Test func stopwatchLapsAndPause() {
        let t0 = Date(timeIntervalSince1970: 0)
        var s = Stopwatch.started(now: t0)
        s.lap(now: t0.addingTimeInterval(30))
        s.pause(now: t0.addingTimeInterval(50))
        #expect(s.elapsed(now: t0.addingTimeInterval(500)) == 50)
        s.resume(now: t0.addingTimeInterval(100))
        s.lap(now: t0.addingTimeInterval(125))
        #expect(s.laps == [30, 75])
        #expect(s.lapDurations == [45, 30])
    }

    @Test func karaokeWordsAndRomanization() {
        let l = Lyrics.parseLRC("[00:10.00]<00:10.00>Di <00:10.50>bawah <00:11.20>langit")
        let line = l.lines[0]
        #expect(line.text == "Di bawah langit")
        #expect(line.words?.map(\.time) == [10, 10.5, 11.2])
        #expect(Lyrics.litWords(line, at: 10.6) == 2)
        #expect(Lyrics.litWords(Lyrics.Line(time: 0, text: "x"), at: 0) == Int.max)
        // Character-tagged lines (Japanese, Chinese) get no spaces added.
        let cjk = Lyrics.parseLRC("[00:01.00]<00:01.00>こ<00:01.20>ん<00:01.40>に").lines[0]
        #expect(cjk.text == "こんに" && cjk.words?.count == 3)

        #expect(Lyrics.romanized("Lampu kota") == nil)
        #expect(Lyrics.romanized("밤하늘 아래")?.lowercased().contains("bam") == true)
        #expect(Lyrics.romanized("こんにちは")?.lowercased().replacingOccurrences(of: "'", with: "") == "konnichiha")
        #expect(Lyrics.romanized("你好") == "ni hao")
    }

    @Test func notificationHistoryGroupsAndPrunes() {
        let t0 = Date(timeIntervalSince1970: 100_000)
        var h = NotificationHistory()
        h.add(.init(app: "WhatsApp", title: "Rani", body: "1", at: t0.addingTimeInterval(-90_000)))
        h.add(.init(app: "WhatsApp", title: "Rani", body: "2", at: t0.addingTimeInterval(-60)))
        h.add(.init(app: "Slack", title: "#ops", body: "x", at: t0.addingTimeInterval(-30), held: true))
        h.add(.init(app: "WhatsApp", title: "Rani", body: "3", at: t0))
        #expect(h.groups.map(\.latest.body) == ["3", "x"])
        #expect(h.groups.first?.count == 3)
        #expect(h.heldCount == 1)
        h.prune(now: t0, keep: 86400)
        #expect(h.groups.first?.count == 2)
        h.releaseHeld()
        #expect(h.heldCount == 0)
    }

    @Test func flashcardsImportAndSchedule() {
        let csv = """
        #separator:tab
        Dosis maks paracetamol?\t4 g/hari
        "Antidot, opioid",Nalokson
        bad line
        """
        let cards = FlashcardDeck.parse(csv)
        #expect(cards.map(\.front) == ["Dosis maks paracetamol?", "Antidot, opioid"])
        #expect(FlashcardDeck.parse("Q;A").first?.back == "A")
        #expect(FlashcardDeck.parse("<b>Q</b>\tA<br>B").first.map { [$0.front, $0.back] } == ["Q", "A B"])

        let t0 = Date(timeIntervalSince1970: 0)
        var deck = FlashcardDeck(name: "Farmako", cards: cards)
        #expect(deck.dueCount(now: t0) == 2)
        let first = deck.nextDue(now: t0)!
        deck.answer(first.id, knew: true, now: t0)
        #expect(deck.dueCount(now: t0) == 1)
        #expect(deck.dueCount(now: t0.addingTimeInterval(86400)) == 2)
        let second = deck.nextDue(now: t0)!
        deck.answer(second.id, knew: false, now: t0)
        #expect(deck.nextDue(now: t0) == nil)
        #expect(deck.nextDue(now: t0.addingTimeInterval(61))?.id == second.id)
        #expect(deck.learned == 1)
    }
}
