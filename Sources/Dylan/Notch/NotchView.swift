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
        if m.hud != nil && m.notchState != .peek { return .compact }
        if m.notchState == .peek && !m.center.slots(fullscreen: m.fullscreen).isEmpty { return .peek }
        return m.center.slots(fullscreen: m.fullscreen).isEmpty && !dotsVisible(m) ? .closed : .compact
    }

    static func dotsVisible(_ m: AppModel) -> Bool { m.cameraOn || m.micOn || m.presentationMode }

    /// Closed but with a privacy dot / presentation indicator: tiny ears only.
    static func dotsOnly(_ m: AppModel) -> Bool {
        displayState(m) == .compact && m.center.slots(fullscreen: m.fullscreen).isEmpty && m.hud == nil
    }

    static func expandedHeight(_ m: AppModel) -> CGFloat {
        switch m.selectedTab {
        case .home: return m.isDeveloper && !m.agents.active.isEmpty ? 330 : 300
        case .media: return 300
        case .clipboard: return 380
        case .shelf: return 236
        case .discord: return 300
        case .stats: return 366
        case .thermal: return FanProvider.shared.hasFans ? 300 : 236
        case .dev: return 316
        case .terminal: return 330
        case .agents: return 312
        }
    }

    static func islandSize(_ m: AppModel, _ g: NotchGeometry) -> CGSize {
        let state = displayState(m)
        if state == .compact && dotsOnly(m) { return CGSize(width: g.notch.width + 36, height: g.notch.height) }
        return g.size(for: state, wide: [.media, .clipboard, .dev].contains(m.selectedTab), expandedHeight: expandedHeight(m))
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
                island(radius: radius, hasNotch: g.hasNotch)
                    .frame(width: size.width + (g.hasNotch ? 2 * DY.shoulder : 0), height: size.height)
                    .overlay(PulseRing(token: model.pulse, radius: radius, hasNotch: g.hasNotch))
                    .matchedGeometryEffect(id: "island", in: ns)
                content(state: state, g: g)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .clipShape(Rectangle())
            }
            .contentShape(shape(radius: radius, hasNotch: g.hasNotch))
            .onTapGesture { if state != .expanded { withAnimation(anim) { model.notchState = .expanded } } }
            // Files dropped on the island go to the shelf (PRD §F1: the notch is a drop zone).
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard model.features.isEnabled(.shelf) else { return false }
                ShelfDrop.accept(providers); return true
            }
            .accessibilityElement(children: .contain)
            .padding(.top, g.hasNotch ? 0 : NotchGeometry.pillTop)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(anim, value: state)
        .animation(anim, value: size)
        .environment(\.locale, L10n.locale)
    }

    /// Black always on a real notch; the pill may use Liquid Glass on macOS 26+ (FR-78, design D15).
    @ViewBuilder private func island(radius: CGFloat, hasNotch: Bool) -> some View {
        if !hasNotch, model.glassPill, #available(macOS 26, *) {
            Color.clear.glassEffect(.regular.tint(.black.opacity(0.35)), in: PillShape(radius: radius))
        } else {
            shape(radius: radius, hasNotch: hasNotch).fill(DY.shape)
        }
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
            if let h = model.hud {
                HUDEars(symbol: h.symbol, value: h.value, notchWidth: g.notch.width, height: g.notch.height).transition(.dyContent)
            } else {
                CompactEars(slots: slots, notchWidth: g.notch.width, height: g.notch.height, dotsOnly: Self.dotsOnly(model))
                    .transition(.dyContent)
            }
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

/// HUD in the ears (D29): icon left, 64 pt bar with 16 steps right; the shape does not resize.
struct HUDEars: View {
    var symbol: String
    var value: Double
    var notchWidth: CGFloat
    var height: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 14)
            Color.clear.frame(width: notchWidth)
            ProgressBar(progress: (value * 16).rounded() / 16, color: .white).frame(width: 64, height: 4)
                .animation(.easeOut(duration: 0.12), value: value)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 14)
        }
        .frame(height: height)
        .accessibilityElement().accessibilityLabel(L("hud.volume", Int(value * 100)))
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
        case .discord where activity.id == "discord-voice":
            DiscordAvatars(size: 18)
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
        case .capture where activity.id == "recording":
            HStack(spacing: 5) { Circle().fill(DY.fail).frame(width: 7, height: 7); Elapsed(since: activity.startedAt) }
        case .notify where activity.id == "faceunlock":
            // D21: the time in Compact, the match score in Peek (carried in `progress`), "Dimatikan" in red.
            if activity.state == .failure {
                ValueText(text: activity.value, color: DY.fail)
            } else if let score = activity.progress, NotchRootView.displayState(model) == .peek {
                ValueText(text: L("faceUnlock.score", score.formatted(.number.precision(.fractionLength(2)).locale(L10n.locale))), color: DY.fg2)
            } else {
                ValueText(text: activity.value)
            }
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
             .script where activity.state == .running && activity.progress == nil, .capture where activity.id == "recording":
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
                .foregroundStyle(activity.id == "recording" ? DY.fail
                                 : DY.color(for: activity.state == .running || activity.state == .ambient ? .running : activity.state))
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
            if activity.kind == .capture, let path = activity.url?.hasPrefix("capture:") == true ? String(activity.url!.dropFirst(8)) : nil {
                CaptureThumb(path: path)
                SwiftUI.Text(model.displayDetail(activity)).font(DY.font(12, .regular)).foregroundStyle(DY.fg).lineLimit(1)
                Spacer(minLength: 4)
                ForEach(Array(model.actions(for: activity).enumerated()), id: \.offset) { _, a in
                    NotchButton(title: a.0, kind: a.1) { model.perform(a.2) }
                }
            } else if activity.kind == .capture, let path = activity.url?.hasPrefix("saved:") == true ? String(activity.url!.dropFirst(6)) : nil {
                // Saved from the editor (like Shottr): the whole row reveals the file in Finder.
                CaptureThumb(path: path)
                VStack(alignment: .leading, spacing: 1) {
                    SwiftUI.Text(model.displayDetail(activity)).font(DY.font(12, .semibold)).foregroundStyle(DY.fg).lineLimit(1)
                    SwiftUI.Text(model.presentationMode ? URL(fileURLWithPath: path).lastPathComponent : (path as NSString).abbreviatingWithTildeInPath)
                        .font(DY.font(11, .regular)).foregroundStyle(DY.fg2).lineLimit(1).truncationMode(.middle)
                }
                .contentShape(Rectangle())
                .onTapGesture { model.perform(.revealFile(path)) }
                Spacer(minLength: 4)
                ForEach(Array(model.actions(for: activity).enumerated()), id: \.offset) { _, a in
                    NotchButton(title: a.0, kind: a.1) { model.perform(a.2) }
                }
            } else if activity.kind == .media, let m = model.media {
                SwiftUI.Text(model.presentationMode ? m.title : "\(m.title) · \(m.artist)")
                    .font(DY.font(12.5, .regular)).foregroundStyle(DY.fg).lineLimit(1)
                Spacer(minLength: 4)
                if m.duration > 0 {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        ValueText(text: DurationFormat.running(m.livePosition(ctx.date)), color: DY.fg2)
                    }
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

// Spinner and equalizer are Core Animation layers: the render server animates them, so a long agent
// run or song costs no per-frame SwiftUI layout (the TimelineView version cost ~9% CPU on an M1 Pro).
struct Spinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if Snapshot.rendering {   // ImageRenderer cannot draw AppKit layers
                Circle().trim(from: 0.15, to: 0.85).stroke(DY.fg, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            } else {
                LayerAnimation(kind: .spinner, color: NSColor(DY.fg), animating: !reduceMotion)
            }
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}

/// Four bars; decorative in v1.0 (real visualizer is FR-63, v1.3).
struct Equalizer: View {
    var playing: Bool
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if Snapshot.rendering {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in Capsule().fill(color).frame(width: 2.5, height: 14 * (playing ? [0.5, 0.9, 0.6, 0.8][i] : 0.3)) }
                }
            } else {
                LayerAnimation(kind: .equalizer, color: NSColor(color), animating: playing && !reduceMotion)
            }
        }
        .frame(width: 16, height: 14)
        .accessibilityHidden(true)
    }
}

private struct LayerAnimation: NSViewRepresentable {
    enum Kind { case spinner, equalizer }
    var kind: Kind
    var color: NSColor
    var animating: Bool
    func makeNSView(context: Context) -> LayerAnimationView { LayerAnimationView(kind: kind) }
    func updateNSView(_ v: LayerAnimationView, context: Context) { v.update(color: color.cgColor, animating: animating) }
}

private final class LayerAnimationView: NSView, LevelView {
    private let kind: LayerAnimation.Kind
    private var shapes: [CAShapeLayer] = []
    private var animating = false

    init(kind: LayerAnimation.Kind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        for _ in 0..<(kind == .spinner ? 1 : 4) {
            let s = CAShapeLayer()
            layer?.addSublayer(s)
            shapes.append(s)
        }
        if kind == .equalizer { VisualizerProvider.shared.register(self) }
    }

    private var showingLevels = false

    /// Real levels (FR-63) replace the decorative animation while they arrive.
    func show(levels: [Float]) {
        guard kind == .equalizer, animating || showingLevels else { return }
        showingLevels = true
        CATransaction.begin(); CATransaction.setAnimationDuration(1.0 / 30)
        for (i, s) in shapes.enumerated() {
            s.removeAnimation(forKey: "dy")
            s.transform = CATransform3DMakeScale(1, CGFloat(0.25 + 0.75 * Double(levels[safe: i] ?? 0)), 1)
        }
        CATransaction.commit()
    }

    func stopLevels() {
        guard showingLevels else { return }
        showingLevels = false
        let was = animating
        animating = !was   // force update() to rebuild the animation
        if let c = shapes.first?.fillColor { update(color: c, animating: was) }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (i, s) in shapes.enumerated() {
            switch kind {
            case .spinner:
                s.frame = bounds
                s.path = CGPath(ellipseIn: bounds.insetBy(dx: 0.8, dy: 0.8), transform: nil)
                s.fillColor = nil; s.lineWidth = 1.6; s.lineCap = .round; s.strokeStart = 0.15; s.strokeEnd = 0.85
            case .equalizer:
                s.frame = CGRect(x: CGFloat(i) * 4.5, y: 0, width: 2.5, height: bounds.height)
                s.path = CGPath(roundedRect: s.bounds, cornerWidth: 1.25, cornerHeight: 1.25, transform: nil)
            }
        }
        CATransaction.commit()
    }

    func update(color: CGColor, animating: Bool) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for s in shapes { if kind == .spinner { s.strokeColor = color } else { s.fillColor = color } }
        CATransaction.commit()
        guard animating != self.animating || (shapes.first?.animation(forKey: "dy") == nil && !showingLevels) else { return }
        if showingLevels && animating { self.animating = animating; return }   // live levels drive the bars
        self.animating = animating
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (i, s) in shapes.enumerated() {
            s.removeAnimation(forKey: "dy")
            if kind == .equalizer { s.transform = animating ? CATransform3DIdentity : CATransform3DMakeScale(1, 0.3, 1) }
            guard animating else { continue }
            let a: CABasicAnimation
            switch kind {
            case .spinner:
                a = CABasicAnimation(keyPath: "transform.rotation.z")
                a.fromValue = 0; a.toValue = -2 * Double.pi   // clockwise (AppKit layers are y-up)
                a.duration = 1
            case .equalizer:
                a = CABasicAnimation(keyPath: "transform.scale.y")
                a.fromValue = 0.3; a.toValue = 1
                a.duration = [0.42, 0.55, 0.36, 0.48][i]
                a.autoreverses = true
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                a.beginTime = CACurrentMediaTime() - Double(i) * 0.13
            }
            a.repeatCount = .infinity
            a.isRemovedOnCompletion = false
            s.add(a, forKey: "dy")
        }
        CATransaction.commit()
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

/// The capture's thumbnail in Peek (D40): drag it straight into Slack, Figma, email, or onto the Shelf.
struct CaptureThumb: View {
    var path: String
    var body: some View {
        Group {
            if let img = Self.thumbnail(path) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.1)
            }
        }
        .frame(width: 46, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.25), lineWidth: 1))
        .onDrag { NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider() }
        .accessibilityLabel(L("shot.dragToApp"))
    }

    /// A small decoded copy, made once: a scroll capture's full PNG is ~160 MB decoded.
    nonisolated(unsafe) private static var cache: [String: NSImage] = [:]
    static func thumbnail(_ path: String) -> NSImage? {
        if let c = cache[path] { return c }
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                   kCGImageSourceThumbnailMaxPixelSize: 160] as CFDictionary) else { return nil }
        let img = NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
        if cache.count > 20 { cache.removeAll() }
        cache[path] = img
        return img
    }
}
