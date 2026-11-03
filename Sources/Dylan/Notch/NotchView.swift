import AppKit
import DylanCore
import SwiftUI

/// The island: one black shape that grows from the notch (design §1–2, D2–D9, D14).
struct NotchRootView: View {
    let layout: NotchLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ns

    private var model: AppModel { AppModel.shared }

    // MARK: Layout rules shared with the controller's hit-testing

    static func displayState(_ m: AppModel) -> NotchState {
        if m.notchState == .expanded { return .expanded }
        if m.notchState == .peek && !m.center.slots(fullscreen: m.fullscreen).isEmpty { return .peek }
        return m.center.slots(fullscreen: m.fullscreen).isEmpty && !dotsVisible(m) ? .closed : .compact
    }

    static func dotsVisible(_ m: AppModel) -> Bool { m.cameraOn || m.micOn || m.presentationMode }

    /// Closed but with a privacy dot / presentation indicator: tiny ears only.
    static func dotsOnly(_ m: AppModel) -> Bool {
        displayState(m) == .compact && m.center.slots(fullscreen: m.fullscreen).isEmpty
    }

    static func expandedHeight(_ m: AppModel) -> CGFloat {
        switch m.selectedTab {
        case .home: return m.isDeveloper && !m.agents.active.isEmpty ? 300 : 270
        case .media: return 300
        case .clipboard: return 380
        case .stats: return 366
        case .agents: return 312
        }
    }

    static func islandSize(_ m: AppModel, _ g: NotchGeometry) -> CGSize {
        let state = displayState(m)
        if state == .compact && dotsOnly(m) { return CGSize(width: g.notch.width + 36, height: g.notch.height) }
        return g.size(for: state, wide: m.selectedTab == .media || m.selectedTab == .clipboard, expandedHeight: expandedHeight(m))
    }

    static func islandFrame(_ m: AppModel, _ g: NotchGeometry) -> CGRect {
        let s = islandSize(m, g)
        let top = g.screen.maxY - (g.hasNotch ? 0 : NotchGeometry.pillTop)
        return CGRect(x: g.centerX - s.width / 2, y: top - s.height, width: s.width, height: s.height)
    }

    // MARK: Body

    var body: some View {
        let g = layout.geometry
        let state = Self.displayState(model)
        let size = Self.islandSize(model, g)
        let radius = g.radius(for: state)
        let anim = reduceMotion ? DY.reduced : DY.spring

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape(radius: radius, hasNotch: g.hasNotch)
                    .fill(DY.shape)
                    .frame(width: size.width + (g.hasNotch ? 2 * DY.shoulder : 0), height: size.height)
                    .overlay(PulseRing(token: model.pulse, radius: radius, hasNotch: g.hasNotch))
                    .matchedGeometryEffect(id: "island", in: ns)
                content(state: state, g: g)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .clipShape(Rectangle())
            }
            .contentShape(shape(radius: radius, hasNotch: g.hasNotch))
            .onTapGesture { if state != .expanded { withAnimation(anim) { model.notchState = .expanded } } }
            .accessibilityElement(children: .contain)
            .padding(.top, g.hasNotch ? 0 : NotchGeometry.pillTop)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(anim, value: state)
        .animation(anim, value: size)
        .environment(\.locale, L10n.locale)
    }

    private func shape(radius: CGFloat, hasNotch: Bool) -> AnyShape {
        hasNotch ? AnyShape(NotchShape(bottomRadius: radius)) : AnyShape(PillShape(radius: radius))
    }

    @ViewBuilder
    private func content(state: NotchState, g: NotchGeometry) -> some View {
        let slots = model.center.slots(fullscreen: model.fullscreen)
        switch state {
        case .closed:
            Color.clear
        case .compact:
            CompactEars(slots: slots, notchWidth: g.notch.width, height: g.notch.height, dotsOnly: Self.dotsOnly(model))
                .transition(.dyContent)
        case .peek:
            VStack(spacing: 0) {
                CompactEars(slots: Array(slots.prefix(1)), notchWidth: g.notch.width, height: g.notch.height, dotsOnly: false)
                if let a = slots.first { PeekRow(activity: a).transition(.dyContent) }
            }
        case .expanded:
            ExpandedView(notchWidth: g.notch.width, notchHeight: g.notch.height).transition(.dyContent)
        }
    }
}

// MARK: Compact (D3–D6)

struct CompactEars: View {
    var slots: [Activity]
    var notchWidth: CGFloat
    var height: CGFloat
    var dotsOnly: Bool
    private var model: AppModel { AppModel.shared }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if dotsOnly { Color.clear }
                else if slots.count >= 2 { EarSummary(activity: slots[0], leading: true) }
                else if let a = slots.first { LeftEar(activity: a) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, dotsOnly ? 0 : 12)

            Color.clear.frame(width: notchWidth)

            HStack(spacing: 6) {
                if slots.count >= 2 { EarSummary(activity: slots[1], leading: false) }
                else if let a = slots.first { RightEar(activity: a) }
                StatusDots()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, dotsOnly ? 8 : 12)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slots.map { model.displayDetail($0) }.joined(separator: ", "))
    }
}

/// Icon + label (single activity, left ear).
struct LeftEar: View {
    var activity: Activity
    private var model: AppModel { AppModel.shared }

    var body: some View {
        HStack(spacing: 6) {
            Glyph(activity: activity)
            // Commands keep the spinner next to their clock in the right ear (design D4).
            if activity.state == .running && [.agent, .script].contains(activity.kind) { Spinner() }
            if activity.kind != .media {
                SwiftUI.Text(model.displayLabel(activity))
                    .font(DY.font(12))
                    .foregroundStyle(DY.color(for: activity.state == .running ? .running : activity.state))
                    .lineLimit(1)
            }
        }
    }
}

/// Value side of a single activity (right ear).
struct RightEar: View {
    var activity: Activity
    private var model: AppModel { AppModel.shared }

    var body: some View {
        switch activity.kind {
        case .media:
            Equalizer(playing: model.media?.isPlaying ?? false, color: model.mediaAccent)
        case .timer:
            HStack(spacing: 5) {
                TimerRing(progress: activity.progress ?? 0, size: 14)
                ValueText(text: activity.value)
            }
        case .script where activity.progress != nil && activity.state == .running:
            HStack(spacing: 5) {
                ProgressBar(progress: activity.progress ?? 0).frame(width: 28, height: 3)
                ValueText(text: activity.value)
            }
        case .command where activity.state == .running:
            HStack(spacing: 5) { Spinner(); Elapsed(since: activity.startedAt) }
        case .script where activity.state == .running:
            Elapsed(since: activity.startedAt)
        case .meeting:
            Countdown(meetingStart: activity.startedAt.addingTimeInterval(MeetingSchedule.soonWindow),
                      color: activity.priority == .p0 ? DY.action : DY.fg)
        default:
            let v = model.displayValue(activity)
            ValueText(text: activity.kind == .agent && activity.state == .running && model.presentationMode ? "" : v,
                      color: activity.state == .needsAction ? DY.action : DY.fg)
        }
    }
}

/// Duo: each ear shows one activity as icon + value (design D6, M3).
struct EarSummary: View {
    var activity: Activity
    var leading: Bool
    private var model: AppModel { AppModel.shared }

    var body: some View {
        HStack(spacing: 5) {
            if leading {
                Glyph(activity: activity)
                if activity.state == .running && [.agent, .command, .script].contains(activity.kind) { Spinner() }
                value
            } else {
                if activity.kind == .media {
                    Equalizer(playing: model.media?.isPlaying ?? false, color: model.mediaAccent)
                } else {
                    Glyph(activity: activity)
                    value
                }
            }
        }
    }

    @ViewBuilder private var value: some View {
        switch activity.kind {
        case .agent where activity.state == .running, .command where activity.state == .running,
             .script where activity.state == .running && activity.progress == nil:
            Elapsed(since: activity.startedAt)
        case .media:
            EmptyView()
        case .meeting:
            Countdown(meetingStart: activity.startedAt.addingTimeInterval(MeetingSchedule.soonWindow),
                      color: activity.priority == .p0 ? DY.action : DY.fg)
        case .timer:
            ValueText(text: activity.value)
        default:
            ValueText(text: model.displayValue(activity), color: activity.state == .needsAction ? DY.action : DY.fg)
        }
    }
}

struct Glyph: View {
    var activity: Activity
    private var model: AppModel { AppModel.shared }

    var body: some View {
        if activity.kind == .media, let art = model.media?.artwork {
            Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: activity.kind == .media ? "music.note" : activity.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DY.color(for: activity.state == .running || activity.state == .ambient ? .running : activity.state))
                .frame(width: 14)
        }
    }
}

struct StatusDots: View {
    private var model: AppModel { AppModel.shared }
    var body: some View {
        HStack(spacing: 4) {
            if model.presentationMode {
                Image(systemName: "eye.slash").font(.system(size: 10, weight: .semibold)).foregroundStyle(DY.fg2)
                    .accessibilityLabel(L("presentation.on"))
            }
            if model.cameraOn { Circle().fill(DY.camDot).frame(width: 7, height: 7).accessibilityLabel(L("privacy.camera")) }
            if model.micOn { Circle().fill(DY.micDot).frame(width: 7, height: 7).accessibilityLabel(L("privacy.mic")) }
        }
    }
}

struct ValueText: View {
    var text: String
    var mono = false
    var color: Color = DY.fg
    var body: some View {
        SwiftUI.Text(text)
            .font(mono ? DY.mono : DY.font(12))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.middle)
            .contentTransition(.numericText())
    }
}

struct Elapsed: View {
    var since: Date
    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { ctx in
            ValueText(text: DurationFormat.running(ctx.date.timeIntervalSince(since)))
        }
    }
}

struct Countdown: View {
    var meetingStart: Date
    var color: Color
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            ValueText(text: DurationFormat.countdown(meetingStart.timeIntervalSince(ctx.date)), color: color)
        }
    }
}

// MARK: Peek (D7)

struct PeekRow: View {
    var activity: Activity
    private var model: AppModel { AppModel.shared }

    var body: some View {
        HStack(spacing: 8) {
            if activity.kind == .media, let m = model.media {
                SwiftUI.Text(model.presentationMode ? m.title : "\(m.title) · \(m.artist)")
                    .font(DY.font(12.5, .regular)).foregroundStyle(DY.fg).lineLimit(1)
                Spacer(minLength: 4)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    ValueText(text: DurationFormat.running(m.livePosition(ctx.date)), color: DY.fg2)
                }
                MediaButtons(size: 12)
            } else {
                detail
                Spacer(minLength: 4)
                ForEach(Array(model.actions(for: activity).enumerated()), id: \.offset) { _, a in
                    NotchButton(title: a.0, kind: a.1) { model.perform(a.2) }
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: NotchGeometry.peekExtra)
    }

    @ViewBuilder private var detail: some View {
        let text = model.displayDetail(activity)
        if activity.kind == .agent && activity.state == .needsAction && !model.presentationMode,
           let space = text.firstIndex(of: " ") {
            HStack(spacing: 5) {
                SwiftUI.Text(text[..<space]).font(DY.font(12, .semibold)).foregroundStyle(DY.action)
                SwiftUI.Text(text[text.index(after: space)...]).font(DY.mono).foregroundStyle(DY.fg).lineLimit(1)
            }
        } else {
            SwiftUI.Text(text).font(DY.font(12.5, .regular)).foregroundStyle(DY.fg).lineLimit(1).truncationMode(.tail)
        }
    }
}

struct MediaButtons: View {
    var size: CGFloat
    private var model: AppModel { AppModel.shared }
    var body: some View {
        HStack(spacing: size * 0.9) {
            iconButton("backward.fill", L("media.previous")) { model.perform(.mediaPrevious) }
            iconButton(model.media?.isPlaying == true ? "pause.fill" : "play.fill", L("media.playPause")) { model.perform(.mediaPlayPause) }
            iconButton("forward.fill", L("media.next")) { model.perform(.mediaNext) }
        }
    }

    private func iconButton(_ s: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: s).font(.system(size: size, weight: .semibold)).foregroundStyle(.white)
                .frame(width: size * 2, height: size * 2).contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(label)
    }
}

// MARK: Small animated pieces

/// Spinner drawn in SwiftUI (renders in snapshots, stops for Reduce Motion).
struct Spinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            Circle().trim(from: 0.15, to: 0.85)
                .stroke(DY.fg, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .frame(width: 10, height: 10)
                .rotationEffect(.degrees(reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
        }
        .accessibilityHidden(true)
    }
}

/// Four bars; decorative in v1.0 (real visualizer is FR-63, v1.3).
struct Equalizer: View {
    var playing: Bool
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing || reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let h = playing && !reduceMotion ? 0.3 + 0.7 * abs(sin(t * (3.1 + Double(i) * 1.3) + Double(i))) : 0.3
                    Capsule().fill(color).frame(width: 2.5, height: 14 * h)
                }
            }
            .frame(height: 14)
        }
        .accessibilityHidden(true)
    }
}

struct TimerRing: View {
    var progress: Double
    var size: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: size / 7)
            Circle().trim(from: 0, to: max(0.001, 1 - progress))
                .stroke(DY.fg, style: StrokeStyle(lineWidth: size / 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

struct ProgressBar: View {
    var progress: Double
    var color: Color = DY.fg
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(color).frame(width: g.size.width * min(1, max(0, progress)))
            }
        }
    }
}

/// One amber ring 0 → 16 pt, opacity 0.65 → 0, 1.2 s, once (design M4).
struct PulseRing: View {
    var token: Int
    var radius: CGFloat
    var hasNotch: Bool
    @StateBox private var phase: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if hasNotch { NotchShape(bottomRadius: radius).stroke(DY.action, lineWidth: 2) }
            else { PillShape(radius: radius).stroke(DY.action, lineWidth: 2) }
        }
        .scaleEffect(1 + 0.08 * phase, anchor: .top)
        .opacity(0.65 * (1 - phase))
        .allowsHitTesting(false)
        .onChange(of: token) {
            guard !reduceMotion else { return }
            phase = 0
            withAnimation(.easeOut(duration: 1.2)) { phase = 1 }
        }
    }
}
