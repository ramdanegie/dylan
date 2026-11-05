import Foundation
import Testing
@testable import DylanCore

private let t0 = Date(timeIntervalSince1970: 3_000_000)

@Suite struct TextRulesTests {
    @Test func truncation() {
        #expect(TextRules.truncateTail("hello world", max: 6) == "hello…")
        #expect(TextRules.truncateTail("short", max: 10) == "short")
        let m = TextRules.truncateMiddle("AuthServiceProvider.swift", max: 16)
        #expect(m.count == 16)
        #expect(m.hasSuffix(".swift"))
        #expect(m.contains("…"))
        #expect(TextRules.abbreviatePath("/Users/gg/dev/api/.env", home: "/Users/gg") == "~/dev/api/.env")
        #expect(TextRules.abbreviatePath("/Users/gg", home: "/Users/gg") == "~")
        #expect(TextRules.abbreviatePath("/Users/ggx/a", home: "/Users/gg") == "/Users/ggx/a")
    }

    @Test(arguments: [
        ("npm test", "npm test"), ("npm run build --prod", "build"), ("pnpm run lint", "lint"),
        ("cargo build --release", "cargo build"), ("make", "make"), ("ls -la", "ls"),
        ("NODE_ENV=test npm test", "npm test"), ("/usr/local/bin/swift build", "swift build"),
        ("sleep 4; false", "sleep 4"), ("npm test && npm run build", "npm test"), ("git log | less", "git log"),
    ])
    func commandShortName(_ input: String, _ expected: String) {
        #expect(TextRules.commandShortName(input) == expected)
    }

    @Test func firstSentence() {
        #expect(TextRules.firstSentence("Selesai. Semua test lulus.") == "Selesai.")
        #expect(TextRules.firstSentence("## Ringkasan\n\n**Menambahkan** `refresh` token!\nLain") == "Menambahkan refresh token!")
        #expect(TextRules.firstSentence("v2.4.1 deployed") == "v2.4.1 deployed")
    }

    @Test func durations() {
        #expect(DurationFormat.result(48) == "48s")
        #expect(DurationFormat.result(252) == "4m 12s")
        #expect(DurationFormat.result(3725) == "1h 02m")
        #expect(DurationFormat.running(83) == "1:23")
        #expect(DurationFormat.running(3723) == "1:02:03")
        #expect(DurationFormat.countdown(600) == "10m")
        #expect(DurationFormat.countdown(541) == "10m")
        #expect(DurationFormat.countdown(58) == "0:58")
        #expect(DurationFormat.long(80 * 60, language: "id") == "1 j 20 m")
        #expect(DurationFormat.long(80 * 60, language: "en") == "1 h 20 m")
        #expect(DurationFormat.long(38 * 60, language: "en") == "38 m")
        #expect(DurationFormat.diff(added: 120, removed: 8) == "+120 \u{2212}8")
    }
}

@Suite struct CommandTests {
    @Test(arguments: ["vim a.txt", "sudo vim /etc/hosts", "ssh prod", "tail -f log", "less -R x", "npm run dev",
                      "docker compose up -d", "claude", "FOO=1 nvim", "git log | less", "   "])
    func ignored(_ c: String) {
        // "git log | less" is not ignored by the first-word rule; it is a pipe, so it should still be tracked.
        if c == "git log | less" { #expect(!CommandFilter().isIgnored(c)) } else { #expect(CommandFilter().isIgnored(c)) }
    }

    @Test(arguments: ["npm test", "sleep 12 && false", "swift build", "npm run build", "docker compose build", "vimdiff-helper"])
    func tracked(_ c: String) { #expect(!CommandFilter().isIgnored(c)) }

    @Test func trackerThresholds() {
        var t = CommandTracker()
        t.start(shellPid: 1, command: "sleep 12 && false", cwd: "/tmp", app: nil, now: t0)
        t.start(shellPid: 2, command: "vim x", cwd: "/tmp", app: nil, now: t0)
        #expect(t.visible(now: t0.addingTimeInterval(9.9)).isEmpty)
        #expect(t.visible(now: t0.addingTimeInterval(10)).map(\.shellPid) == [1])
        let r = t.end(shellPid: 1, status: 1, now: t0.addingTimeInterval(12))
        #expect(r?.status == 1 && r?.duration == 12)
        #expect(t.end(shellPid: 2, status: 0, now: t0.addingTimeInterval(20)) == nil)

        t.start(shellPid: 3, command: "ls", cwd: "/", app: nil, now: t0)
        #expect(t.end(shellPid: 3, status: 0, now: t0.addingTimeInterval(1)) == nil)
    }

    /// Review finding: preexec and precmd send from separate background processes, so `end` can win the race.
    @Test func lateStartAfterEndIsIgnored() {
        var t = CommandTracker()
        #expect(t.end(shellPid: 7, status: 0, seq: 1, now: t0) == nil)     // end of "cd" arrives first
        t.start(shellPid: 7, command: "cd src", cwd: "/", app: nil, seq: 1, now: t0)
        #expect(t.running[7] == nil)                                         // no phantom command
        t.start(shellPid: 7, command: "npm test", cwd: "/", app: nil, seq: 2, now: t0)
        #expect(t.end(shellPid: 7, status: 0, seq: 1, now: t0.addingTimeInterval(20)) == nil)  // stale end
        #expect(t.running[7] != nil)
        #expect(t.end(shellPid: 7, status: 1, seq: 2, now: t0.addingTimeInterval(20))?.status == 1)
    }

    @Test func resultVisibility() {
        let f = CommandFilter()
        #expect(f.shouldShowResult(duration: 12, terminalFrontmost: false, always: false))
        #expect(!f.shouldShowResult(duration: 12, terminalFrontmost: true, always: false))
        #expect(f.shouldShowResult(duration: 12, terminalFrontmost: true, always: true))
        #expect(!f.shouldShowResult(duration: 5, terminalFrontmost: false, always: true))
    }
}

@Suite struct MeetingTests {
    @Test(arguments: [
        ("Join: https://us02web.zoom.us/j/81234567890?pwd=abc123 thanks", MeetingLink.Service.zoom),
        ("https://meet.google.com/abc-defg-hij", .meet),
        ("Teams https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0?context=%7b%7d", .teams),
        ("https://teams.live.com/meet/9876543210", .teams),
    ])
    func finds(_ text: String, _ service: MeetingLink.Service) {
        #expect(MeetingLink.find(in: [nil, text])?.service == service)
    }

    @Test func zoomAppURL() throws {
        let l = try #require(MeetingLink.find(in: ["https://us02web.zoom.us/j/81234567890?pwd=abc123."]))
        #expect(l.url.absoluteString == "https://us02web.zoom.us/j/81234567890?pwd=abc123")
        #expect(l.appURL?.absoluteString == "zoommtg://zoom.us/join?action=join&confno=81234567890&pwd=abc123")
    }

    @Test func firstFieldWinsAndNoFalsePositives() {
        let l = MeetingLink.find(in: ["https://meet.google.com/abc-defg-hij", "https://zoom.us/j/1"])
        #expect(l?.service == .meet)
        #expect(MeetingLink.find(in: ["https://zoom.us/pricing", "meet.google.com", "rapat di ruang 3"]) == nil)
    }

    @Test func phases() {
        let e = MeetingSchedule.Event(id: "s", title: "Standup", start: t0.addingTimeInterval(600), end: t0.addingTimeInterval(1500), link: nil)
        let allDay = MeetingSchedule.Event(id: "h", title: "Libur", start: t0, end: t0.addingTimeInterval(86400), link: nil, isAllDay: true)
        #expect(MeetingSchedule.current([e, allDay], now: t0.addingTimeInterval(-1)) == nil)
        #expect(MeetingSchedule.current([e], now: t0)?.1 == .soon)
        #expect(MeetingSchedule.current([e], now: t0.addingTimeInterval(540))?.1 == .imminent)
        #expect(MeetingSchedule.current([e], now: t0.addingTimeInterval(900))?.1 == .imminent)
        #expect(MeetingSchedule.current([e], now: t0.addingTimeInterval(901)) == nil)
        #expect(MeetingSchedule.current([e], now: t0, dismissed: ["s"]) == nil)
        #expect(MeetingSchedule.nextChange([e], now: t0.addingTimeInterval(-10)) == t0)
        #expect(MeetingSchedule.nextChange([e], now: t0) == t0.addingTimeInterval(540))
    }
}

@Suite struct TimerTests {
    @Test func wallClockSurvivesSleep() {
        let t = CountdownTimer.quick(300, now: t0)
        #expect(t.remaining(now: t0.addingTimeInterval(120)) == 180)
        #expect(t.isFinished(now: t0.addingTimeInterval(301)))   // laptop slept through the end
    }

    @Test func pauseResume() {
        var t = CountdownTimer.quick(300, now: t0)
        t.pause(now: t0.addingTimeInterval(100))
        #expect(t.remaining(now: t0.addingTimeInterval(1000)) == 200)
        t.resume(now: t0.addingTimeInterval(1000))
        #expect(t.remaining(now: t0.addingTimeInterval(1050)) == 150)
    }

    @Test func pomodoroCycle() {
        var t = CountdownTimer.pomodoro(now: t0)
        var phases: [CountdownTimer.Phase] = [t.phase]
        var cfg = PomodoroConfig(); cfg.autoFocus = true
        for _ in 0..<8 { t = t.next(now: t0, config: cfg)!; phases.append(t.phase) }
        #expect(phases == [.focus, .shortBreak, .focus, .shortBreak, .focus, .shortBreak, .focus, .longBreak, .focus])
        #expect(CountdownTimer.quick(5, now: t0).next(now: t0) == nil)
    }

    @Test(arguments: [("45m", 2700.0), ("1h30", 5400), ("1h 30m", 5400), ("1j30m", 5400), ("90s", 90), ("10", 600), ("1:30", 90), ("2h", 7200)])
    func parse(_ s: String, _ v: Double) { #expect(DurationParser.parse(s) == v) }

    @Test(arguments: ["", "abc", "0", "1:75", "m", "999999999999999999", "25h", "9999999m"])
    func parseRejects(_ s: String) { #expect(DurationParser.parse(s) == nil) }
}

@Suite struct BatteryTests {
    @Test func transitions() {
        let bat80 = BatterySnapshot(percent: 80, isCharging: false, onAC: false)
        let ac80 = BatterySnapshot(percent: 80, isCharging: true, onAC: true)
        #expect(BatteryLogic.events(from: nil, to: bat80).isEmpty)
        #expect(BatteryLogic.events(from: bat80, to: ac80) == [.pluggedIn])
        #expect(BatteryLogic.events(from: ac80, to: bat80) == [.unplugged])
        #expect(BatteryLogic.events(from: BatterySnapshot(percent: 99, isCharging: true, onAC: true),
                                    to: BatterySnapshot(percent: 100, isCharging: false, onAC: true)) == [.full])
        #expect(BatteryLogic.events(from: BatterySnapshot(percent: 21, isCharging: false, onAC: false),
                                    to: BatterySnapshot(percent: 20, isCharging: false, onAC: false)) == [.low20])
        #expect(BatteryLogic.events(from: BatterySnapshot(percent: 20, isCharging: false, onAC: false),
                                    to: BatterySnapshot(percent: 19, isCharging: false, onAC: false)).isEmpty)
        #expect(BatteryLogic.events(from: BatterySnapshot(percent: 11, isCharging: false, onAC: false),
                                    to: BatterySnapshot(percent: 10, isCharging: false, onAC: false)) == [.low10])
        // A jump past both thresholds (sleep) reports only the more urgent one.
        #expect(BatteryLogic.events(from: BatterySnapshot(percent: 30, isCharging: false, onAC: false),
                                    to: BatterySnapshot(percent: 8, isCharging: false, onAC: false)) == [.low10])
    }
}

@Suite struct ProfileTests {
    @Test func developerFeaturesNeedDeveloperProfile() {
        var f = FeatureSet(profile: .general)
        #expect(!f.isEnabled(.agents) && !f.isEnabled(.commands))
        f.toggles[.agents] = true
        #expect(!f.isEnabled(.agents))   // a toggle cannot bypass the profile
        f.profile = .developer
        #expect(f.isEnabled(.agents))
        #expect(f.isEnabled(.media) && !f.isEnabled(.bluetooth))
        f.toggles[.media] = false
        #expect(!f.enabled.contains(.media))
    }

    @Test func language() {
        #expect(LanguageChoice.from(appleLanguages: nil) == .system)
        #expect(LanguageChoice.from(appleLanguages: ["id-ID"]) == .indonesian)
        #expect(LanguageChoice.english.appleLanguages == ["en"])
        #expect(LanguageChoice.system.appleLanguages == nil)
        #expect(LanguageChoice.resolve(.system, systemPreferred: ["fr-FR", "id-ID"]) == "id")
        #expect(LanguageChoice.resolve(.system, systemPreferred: ["fr-FR"]) == "en")
        #expect(LanguageChoice.resolve(.indonesian, systemPreferred: ["en-US"]) == "id")
    }
}
