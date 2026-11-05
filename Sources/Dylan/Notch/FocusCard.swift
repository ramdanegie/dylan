import DylanCore
import SwiftUI

/// Focus card on Home (FR-111, design D58): Pomodoro, Timer and Stopwatch.
struct TimerCard: View {
    enum Mode: Int, CaseIterable { case pomodoro, timer, stopwatch }
    @StateBox private var input = ""
    @StateBox private var mode = Mode.pomodoro
    private var model: AppModel { AppModel.shared }

    var body: some View {
        VStack(spacing: 8) {
            if let t = model.timer { running(t) }
            else if let s = model.stopwatch { stopwatch(s) }
            else { idle }
        }
    }

    @ViewBuilder private func running(_ t: CountdownTimer) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            ZStack {
                TimerRing(progress: t.progress(now: ctx.date), size: 84)
                VStack(spacing: 0) {
                    ValueText(text: DurationFormat.running(t.remaining(now: ctx.date))).font(.system(size: 18, weight: .semibold))
                    SwiftUI.Text(t.phase == .timer ? L("timer.timer") : (t.phase == .focus ? L("timer.focus") : L("timer.break")))
                        .font(DY.font(10.5, .regular)).foregroundStyle(DY.fg2)
                }
            }
        }
        if t.phase != .timer {
            SwiftUI.Text(L("timer.cycle", t.focusCount + (t.phase == .focus ? 1 : 0))).font(DY.font(10.5, .regular)).foregroundStyle(DY.fg2)
        }
        HStack(spacing: 6) {
            if t.isBreak {
                if t.isPaused { NotchButton(title: L("focus.startBreak")) { model.perform(.startBreak) } }
                NotchButton(title: L("focus.skip"), kind: t.isPaused ? .quiet : .normal) { model.skipBreak() }
            }
            else {
                NotchButton(title: t.isPaused ? (t.phase == .focus ? L("focus.start") : L("button.resume")) : L("button.pause")) {
                    if t.isPaused { model.perform(.startFocus) } else { model.toggleTimerPause() }
                }
            }
            NotchButton(title: L("button.reset"), kind: .quiet) { model.stopTimer() }
        }
    }

    @ViewBuilder private func stopwatch(_ s: Stopwatch) -> some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            VStack(spacing: 2) {
                SwiftUI.Text(Self.precise(s.elapsed(now: ctx.date))).font(.system(size: 22, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                SwiftUI.Text(L("focus.stopwatch")).font(DY.font(10.5, .regular)).foregroundStyle(DY.fg2)
            }
        }
        .frame(height: 50)
        VStack(spacing: 1) {
            ForEach(Array(s.lapDurations.prefix(2).enumerated()), id: \.offset) { i, d in
                HStack {
                    SwiftUI.Text(L("focus.lap", s.laps.count - i)).foregroundStyle(DY.fg2)
                    Spacer()
                    SwiftUI.Text(Self.precise(d)).monospacedDigit().foregroundStyle(DY.fg)
                }
                .font(DY.font(10.5, .regular))
            }
        }
        HStack(spacing: 6) {
            NotchButton(title: s.isRunning ? L("button.pause") : L("button.resume")) { model.toggleStopwatch() }
            if s.isRunning { NotchButton(title: L("focus.lapButton")) { model.lapStopwatch() } }
            else { NotchButton(title: L("button.reset"), kind: .quiet) { model.resetStopwatch() } }
        }
    }

    @ViewBuilder private var idle: some View {
        HStack(spacing: 2) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button { mode = m } label: {
                    SwiftUI.Text(L("focus.mode.\(m)")).font(DY.font(10, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(mode == m ? .black : DY.fg2)
                        .frame(maxWidth: .infinity, minHeight: 20)
                        .background(Capsule().fill(mode == m ? Color.white : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2).background(Capsule().fill(DY.control))
        switch mode {
        case .pomodoro:
            let p = Prefs.shared
            SwiftUI.Text(L("focus.pomoSummary", p.focusMinutes, p.shortBreakMinutes)).font(DY.font(10.5, .regular)).foregroundStyle(DY.fg2)
            NotchButton(title: L("focus.startPomodoro"), kind: .primaryNeutral) { model.startTimer(.pomodoro(now: Date(), config: p.pomodoro)) }
        case .timer:
            HStack(spacing: 6) {
                ForEach([5, 10, 25], id: \.self) { m in
                    NotchButton(title: "\(m)m") { model.startTimer(.quick(TimeInterval(m * 60), now: Date())) }
                }
            }
            TextField(L("timer.custom"), text: $input)
                .textFieldStyle(.plain).font(DY.font(12, .regular)).foregroundStyle(.white)
                .padding(.horizontal, 10).frame(height: 24)
                .background(Capsule().fill(DY.control))
                .onSubmit {
                    if let d = DurationParser.parse(input) { model.startTimer(.quick(d, now: Date())); input = "" }
                }
        case .stopwatch:
            SwiftUI.Text(L("focus.stopwatchHint")).font(DY.font(10.5, .regular)).foregroundStyle(DY.fg2).multilineTextAlignment(.center)
            NotchButton(title: L("focus.startStopwatch"), kind: .primaryNeutral) { model.startStopwatch() }
        }
    }

    /// 1:02.3 (tenths while under an hour).
    static func precise(_ t: TimeInterval) -> String {
        t >= 3600 ? DurationFormat.running(t) : DurationFormat.running(floor(t)) + "." + String(Int((t * 10).truncatingRemainder(dividingBy: 10)))
    }
}

extension AppModel {
    func startStopwatch() {
        stopwatch = .started(now: Date())
        refreshStopwatch()
    }

    func toggleStopwatch() {
        let now = Date()
        if stopwatch?.isRunning == true { stopwatch?.pause(now: now) } else { stopwatch?.resume(now: now) }
        refreshStopwatch()
    }

    func lapStopwatch() { stopwatch?.lap(now: Date()) }

    func resetStopwatch() {
        stopwatch = nil
        removeIfPresent("stopwatch", now: Date())
    }

    /// Compact shows the running stopwatch; a paused one leaves the ears.
    private func refreshStopwatch() {
        let now = Date()
        guard let s = stopwatch, s.isRunning else { removeIfPresent("stopwatch", now: now); return }
        center.upsert(Activity(id: "stopwatch", kind: .timer, priority: .p2, state: .running, symbol: "stopwatch",
                               label: L("focus.stopwatch"), detail: L("focus.stopwatch"),
                               startedAt: now.addingTimeInterval(-s.elapsed(now: now))))
        scheduleTick()
    }
}
