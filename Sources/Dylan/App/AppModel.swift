import AppKit
import CoreLocation
import DylanCore
import IOKit.pwr_mgt
import Observation
import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case home, media, discord, shelf, clipboard, stats, thermal, agents, dev, terminal
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .media: return "music.note"
        case .clipboard: return "doc.on.clipboard"
        case .shelf: return "tray.and.arrow.down"
        case .discord: return "headphones"
        case .stats: return "chart.bar"
        case .thermal: return "thermometer.medium"
        case .agents: return "sparkle"
        case .dev: return "hammer"
        case .terminal: return "apple.terminal"
        }
    }
    var title: String { L("tab.\(rawValue)") }
}

struct MediaState: Equatable {
    /// browser and vlc come from OtherPlayersProvider (FR-11): no seek, shuffle, repeat or volume there.
    enum Source: String { case spotify, music, browser, vlc }
    var source: Source
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var position: TimeInterval
    var duration: TimeInterval
    var positionAt: Date
    var artwork: NSImage?
    var artworkKey: String?
    var shuffle = false
    var repeating = false
    var volume: Int?
    /// The app playing (for browser/VLC sources; Spotify and Music are known from the source).
    var appBundleID: String?

    var sourceName: String {
        switch source {
        case .spotify: return "Spotify"
        case .music: return "Apple Music"
        case .vlc: return "VLC"
        case .browser: return appBundleID.flatMap { BrowserMedia.browsers[$0] } ?? "Browser"
        }
    }

    var playerBundleID: String? {
        switch source {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        case .vlc: return "org.videolan.vlc"
        case .browser: return appBundleID
        }
    }

    /// Seek, shuffle, repeat and volume exist only for Spotify and Music.
    var hasFullControls: Bool { source == .spotify || source == .music }

    func livePosition(_ now: Date) -> TimeInterval {
        guard isPlaying else { return position }
        return min(duration > 0 ? duration : .infinity, position + now.timeIntervalSince(positionAt))
    }
}

/// A Claude Code permission request waiting on an open socket connection.
struct PendingPermission {
    var requestID: String
    var sessionID: String
    var tool: String?
    var detail: String?
    var createdAt: Date
    var connection: UUID?
    var reply: (PermissionReply) -> Void
}

/// Things the notch can do in response to a button.
enum NotchAction: Equatable {
    case allow(String), deny(String), releaseToTerminal(String)
    case focusSession(String)
    case join(URL)
    case openURL(URL)
    case mediaPrevious, mediaPlayPause, mediaNext
    case dismiss(String)
    case openStats, stopProcess(Int32)
    case revealFile(String), shelveFile(String)
    case discordMute, discordDeafen, discordLeave, discordKeybindMute, openDiscord(URL)
    case meetingControl(MeetingControls.Control)
    /// open / close / reply / accept / decline on a Notification Center banner.
    case banner(String, String)
    /// beautify / save / pin / text / openLink / showText on a screenshot result (D40).
    case capture(String, String)
    /// max / processes on the over-temperature peek (D47).
    case fan(String)
    /// "Riwayat" on the Face Unlock result (D21).
    case faceUnlockHistory
    /// "View" on the update notice.
    case showUpdate
    /// "Clean up" on the low-storage notice (FR-103).
    case openStorage
    /// Stop on the screen recording (FR-94).
    case stopRecording
}

@Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: Settings (persisted in UserDefaults)

    var features: FeatureSet { didSet { save(features, "features"); providersNeedRefresh += 1 } }
    var answerPermissionsFromNotch: Bool { didSet { defaults.set(answerPermissionsFromNotch, forKey: "answerPermissions") } }
    var permissionTimeout: Double { didSet { defaults.set(permissionTimeout, forKey: "permissionTimeout") } }
    var commandResultsAlways: Bool { didSet { defaults.set(commandResultsAlways, forKey: "commandResultsAlways") } }
    var commandThreshold: Double {
        didSet { defaults.set(commandThreshold, forKey: "commandThreshold"); commands.filter.threshold = commandThreshold }
    }
    var duo: Bool { didSet { defaults.set(duo, forKey: "duo"); center.config.maxSlots = duo ? 2 : 1 } }
    var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: "hoverDelay") } }
    var permissionSound: Bool { didSet { defaults.set(permissionSound, forKey: "permissionSound") } }
    /// Keep awake default in minutes; 0 = until turned off.
    var keepAwakeMinutes: Int { didSet { defaults.set(keepAwakeMinutes, forKey: "keepAwakeMinutes") } }
    /// Stop keep awake on battery below this percentage; 0 = never.
    var keepAwakeStopBelow: Int { didSet { defaults.set(keepAwakeStopBelow, forKey: "keepAwakeStopBelow") } }
    var colorFormat: String { didSet { defaults.set(colorFormat, forKey: "colorFormat") } }
    var colorHistory: [String] { didSet { defaults.set(colorHistory, forKey: "colorHistory") } }
    var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: "onboardingDone") } }
    var language: LanguageChoice {
        didSet {
            if let v = language.appleLanguages { defaults.set(v, forKey: "AppleLanguages") }
            else { defaults.removeObject(forKey: "AppleLanguages") }
        }
    }

    // MARK: Live state

    var center = ActivityCenter()
    var agents = AgentSessions()
    var commands = CommandTracker()
    var notchState: NotchState = .closed
    var selectedTab: Tab = .home
    var fullscreen = false
    var presentationMode = false
    var media: MediaState? {
        didSet {
            if media?.isPlaying != oldValue?.isPlaying || media?.source != oldValue?.source { VisualizerProvider.shared.update() }
            if media?.artworkKey != oldValue?.artworkKey { SpotifyAccount.shared.trackChanged(media?.source == .spotify ? media?.artworkKey : nil) }
        }
    }
    var mediaAccent: Color = DY.fg
    var meetings: [MeetingSchedule.Event] = []
    var dismissedMeetings: Set<String> = []
    var timer: CountdownTimer?
    var battery: BatterySnapshot?
    var cameraOn = false
    var micOn = false
    var micApp: String?
    /// Process using the microphone (with micApp), for meeting controls.
    @ObservationIgnored var micAppProcess: (pid: pid_t, bundleID: String?)?
    var screenLocked = false
    var pending: [String: PendingPermission] = [:]
    /// P0 auto-peek (4 s) — design M4.
    var autoPeekUntil: Date?
    /// Bumped to play the one-shot P0 pulse.
    var pulse = 0
    /// Bumped when feature toggles change so providers can start/stop.
    var providersNeedRefresh = 0
    var lastError: String?
    /// Bumped when the clipboard history changes (the provider itself is not observable).
    var clipboardRevision = 0
    @ObservationIgnored var focusClipboardSearch = false
    var clearClipboardOnQuit: Bool { didSet { defaults.set(clearClipboardOnQuit, forKey: "clearClipboardOnQuit") } }
    var quickPlay: [QuickPlayItem] { didSet { save(quickPlay, "quickPlay") } }
    var weatherCity: String { didSet { defaults.set(weatherCity, forKey: "weatherCity") } }
    var discordClientID: String { didSet { defaults.set(discordClientID, forKey: "discordClientID") } }
    var spotifyClientID: String { didSet { defaults.set(spotifyClientID, forKey: "spotifyClientID") } }
    var discordMessages: Bool { didSet { defaults.set(discordMessages, forKey: "discordMessages") } }
    var discordMuteKey: String { didSet { defaults.set(discordMuteKey, forKey: "discordMuteKey") } }
    var discordDeafKey: String { didSet { defaults.set(discordDeafKey, forKey: "discordDeafKey") } }
    /// Git roots seen in agent sessions and terminal commands (newest first), for GitHub CI.
    var recentRepos: [String] { didSet { defaults.set(recentRepos, forKey: "recentRepos") } }
    var screenshotsToShelf: Bool {
        didSet { defaults.set(screenshotsToShelf, forKey: "screenshotsToShelf"); ShelfProvider.shared.restartScreenshotWatch() }
    }
    var keepAwake: KeepAwake?
    var mirrorOn = false
    /// Overlay HUD (design D29): replaces the ear contents for 1.5 s, does not take a Duo slot.
    var hud: (symbol: String, value: Double, until: Date)?
    var accentFromArtwork: Bool { didSet { defaults.set(accentFromArtwork, forKey: "accentFromArtwork"); mediaAccent = accentFromArtwork ? DY.accent(media?.artwork) : DY.fg } }
    var glassPill: Bool { didSet { defaults.set(glassPill, forKey: "glassPill") } }
    var smallCompact: Bool { didSet { defaults.set(smallCompact, forKey: "smallCompact") } }
    /// Bundle IDs that hide the notch while in front (games, Keynote…).
    var hideForApps: [String] { didSet { defaults.set(hideForApps, forKey: "hideForApps") } }
    /// Apps whose notifications show in the notch (FR-68); empty = all.
    var notificationApps: [String] { didSet { defaults.set(notificationApps, forKey: "notificationApps") } }
    var hiddenForFrontApp = false
    var scratchpadOpen = false
    @ObservationIgnored private var keepAwakeAssertion: IOPMAssertionID = 0

    /// Snapshot mode swaps this for a throwaway suite so rendering never touches the user's settings.
    nonisolated(unsafe) static var store = UserDefaults.standard
    private let defaults = AppModel.store
    private var tickTimer: Timer?
    private var permissionTimers: [String: Timer] = [:]
    private var deadShellSince: [Int: Date] = [:]
    /// Sessions whose "waiting for you" notice was already shown (P1: once, then history).
    @ObservationIgnored private var waitingNotified: Set<String> = []

    private init() {
        let d = AppModel.store
        features = (d.data(forKey: "features")).flatMap { try? JSONDecoder().decode(FeatureSet.self, from: $0) } ?? FeatureSet()
        answerPermissionsFromNotch = d.object(forKey: "answerPermissions") as? Bool ?? false
        permissionTimeout = d.object(forKey: "permissionTimeout") as? Double ?? 30
        commandResultsAlways = d.bool(forKey: "commandResultsAlways")
        commandThreshold = d.object(forKey: "commandThreshold") as? Double ?? 10
        duo = d.object(forKey: "duo") as? Bool ?? true
        hoverDelay = d.object(forKey: "hoverDelay") as? Double ?? 0.15
        permissionSound = d.bool(forKey: "permissionSound")
        keepAwakeMinutes = d.object(forKey: "keepAwakeMinutes") as? Int ?? 60
        keepAwakeStopBelow = d.object(forKey: "keepAwakeStopBelow") as? Int ?? 20
        colorFormat = d.string(forKey: "colorFormat") ?? "hex"
        colorHistory = d.stringArray(forKey: "colorHistory") ?? []
        clearClipboardOnQuit = d.bool(forKey: "clearClipboardOnQuit")
        screenshotsToShelf = d.object(forKey: "screenshotsToShelf") as? Bool ?? true
        weatherCity = d.string(forKey: "weatherCity") ?? ""
        discordClientID = d.string(forKey: "discordClientID") ?? ""
        spotifyClientID = d.string(forKey: "spotifyClientID") ?? ""
        discordMessages = d.object(forKey: "discordMessages") as? Bool ?? true
        discordMuteKey = d.string(forKey: "discordMuteKey") ?? "⌃⇧M"
        discordDeafKey = d.string(forKey: "discordDeafKey") ?? "⌃⇧D"
        recentRepos = d.stringArray(forKey: "recentRepos") ?? []
        accentFromArtwork = d.object(forKey: "accentFromArtwork") as? Bool ?? true
        glassPill = d.bool(forKey: "glassPill")
        smallCompact = d.bool(forKey: "smallCompact")
        hideForApps = d.stringArray(forKey: "hideForApps") ?? []
        notificationApps = d.stringArray(forKey: "notificationApps") ?? NotificationRules.defaultApps
        quickPlay = d.data(forKey: "quickPlay").flatMap { try? JSONDecoder().decode([QuickPlayItem].self, from: $0) } ?? []
        onboardingDone = d.bool(forKey: "onboardingDone")
        language = LanguageChoice.from(appleLanguages: d.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String])
        center.config.maxSlots = duo ? 2 : 1
        commands.filter.threshold = commandThreshold
    }

    private func save<T: Encodable>(_ v: T, _ key: String) {
        if let d = try? JSONEncoder().encode(v) { defaults.set(d, forKey: key) }
    }

    var isDeveloper: Bool { features.profile == .developer }

    var tabs: [Tab] {
        var t: [Tab] = [.home, .media]
        // Discord tab only appears when connected (design D26), or to finish setting up.
        if features.isEnabled(.discord) && (DiscordProvider.shared.connected || !discordClientID.isEmpty) { t.append(.discord) }
        if features.isEnabled(.shelf) { t.append(.shelf) }
        if features.isEnabled(.clipboard) { t.append(.clipboard) }
        if features.isEnabled(.stats) { t.append(.stats) }
        if features.isEnabled(.thermal) { t.append(.thermal) }
        if isDeveloper && features.isEnabled(.agents) { t.append(.agents) }
        if isDeveloper && features.isEnabled(.ports) { t.append(.dev) }
        if isDeveloper && features.isEnabled(.terminal) { t.append(.terminal) }
        return t
    }

    // MARK: Ticking (only while something depends on the clock)

    func scheduleTick() {
        let needs = !center.activities.isEmpty || !commands.running.isEmpty || timer != nil || autoPeekUntil != nil || keepAwake != nil
            || MeetingSchedule.nextChange(meetings, now: Date()) != nil
        if needs, tickTimer == nil {
            let t = Timer(timeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { AppModel.shared.tick() } }
            t.tolerance = 0.2
            RunLoop.main.add(t, forMode: .common)
            tickTimer = t
        } else if !needs {
            tickTimer?.invalidate(); tickTimer = nil
        }
    }

    func tick(now: Date = Date()) {
        // Mutate observed state only when something changed: every write re-renders the notch.
        if center.hasExpired(now: now) { center.tick(now: now) }
        if features.isEnabled(.commands) {
            // Terminal tab closed mid-command. A short grace period lets a late `end` (sent in the
            // background just before the shell exited) still arrive and show the result.
            for r in commands.running.values {
                if Self.processAlive(r.shellPid) { deadShellSince[r.shellPid] = nil; continue }
                let since = deadShellSince[r.shellPid] ?? now
                deadShellSince[r.shellPid] = since
                if now.timeIntervalSince(since) >= 3 {
                    deadShellSince[r.shellPid] = nil
                    commands.forget(shellPid: r.shellPid)
                    center.remove(Self.commandKey(r), now: now)
                }
            }
            for r in commands.visible(now: now) where center.activities[Self.commandKey(r)] == nil {
                center.upsert(commandActivity(r))
            }
        }
        // `dylan run` that was killed before it could report.
        for a in center.activities.values where a.id.hasPrefix("script-run-") && a.state == .running {
            if let pid = Int(a.id.dropFirst("script-run-".count)), !Self.processAlive(pid) { center.remove(a.id, now: now) }
        }
        if agents.hasStale(now: now) { agents.expireStale(now: now); refreshAgentActivity(now: now) }
        if let t = timer, t.isFinished(now: now) { timerFinished(now: now) }
        refreshMeeting(now: now)
        if let until = autoPeekUntil, now >= until {   // (read-only until it fires)
            autoPeekUntil = nil
            if notchState == .peek { notchState = .compact }
        }
        if timer != nil { refreshTimerActivity(now: now) }
        if let k = keepAwake, k.shouldStop(now: now, battery: battery, stopBelow: keepAwakeStopBelow) { stopKeepAwake() }
        scheduleTick()
    }

    func clipboardChanged() { clipboardRevision &+= 1 }

    func showHUD(symbol: String, value: Double) {
        hud = (symbol, min(1, max(0, value)), Date().addingTimeInterval(1.5))
        let t = Timer(timeInterval: 1.6, repeats: false) { _ in
            MainActor.assumeIsolated { if let h = AppModel.shared.hud, h.until <= Date() { AppModel.shared.hud = nil } }
        }
        RunLoop.main.add(t, forMode: .common)
    }

    func openClipboard() {
        guard features.isEnabled(.clipboard) else { return }
        focusClipboardSearch = true
        selectedTab = .clipboard
        notchState = .expanded
    }

    // MARK: Keep awake (FR-74)

    func startKeepAwake(minutes: Int? = nil) {
        let m = minutes ?? keepAwakeMinutes
        stopKeepAwake()
        guard IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                          "Dylan: Keep awake" as CFString, &keepAwakeAssertion) == kIOReturnSuccess else { return }
        let now = Date()
        keepAwake = .start(duration: m > 0 ? TimeInterval(m * 60) : nil, now: now)
        center.upsert(Activity(id: "keepawake", kind: .timer, priority: .p2, state: .running, symbol: "cup.and.saucer.fill",
                               label: L("keepAwake.short"), value: m > 0 ? "" : "∞",
                               detail: m > 0 ? L("keepAwake.until", DurationFormat.long(TimeInterval(m * 60), language: L10n.language)) : L("keepAwake.on"),
                               progress: nil, startedAt: now))
        scheduleTick()
    }

    func stopKeepAwake() {
        if keepAwakeAssertion != 0 { IOPMAssertionRelease(keepAwakeAssertion); keepAwakeAssertion = 0 }
        keepAwakeUntilDownloads = false
        guard keepAwake != nil else { return }
        keepAwake = nil
        removeIfPresent("keepawake", now: Date())
    }

    func toggleKeepAwake() { keepAwake == nil ? startKeepAwake() : stopKeepAwake() }

    /// Keep awake "until downloads finish" (FR-74).
    @ObservationIgnored var keepAwakeUntilDownloads = false
    func downloadFinished() {
        if keepAwakeUntilDownloads, !DownloadsProvider.shared.active { keepAwakeUntilDownloads = false; stopKeepAwake() }
    }

    // MARK: Color picker (FR-73)

    func pickColor() {
        guard features.isEnabled(.colorPicker) else { return }
        NSColorSampler().show { picked in
            guard let c = picked?.usingColorSpace(.sRGB) else { return }
            let rgb = PickedColor(r: c.redComponent, g: c.greenComponent, b: c.blueComponent)
            MainActor.assumeIsolated { AppModel.shared.colorPicked(rgb) }
        }
    }

    func colorPicked(_ c: PickedColor) {
        let text: String
        switch colorFormat {
        case "rgb": text = c.rgb
        case "hsl": text = "hsl(\(c.hsl))"
        case "swiftui" where isDeveloper: text = c.swiftUI
        default: text = c.hex
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        colorHistory = Array(([c.hex] + colorHistory.filter { $0 != c.hex }).prefix(20))
        let now = Date()
        center.post(Activity(id: "color-\(c.hex)", kind: .notify, priority: .p1, state: .success, symbol: "eyedropper",
                             label: c.hex, value: L("color.copiedShort"), detail: L("color.copied", text), startedAt: now), now: now)
        scheduleTick()
    }

    // MARK: Bridge messages

    func handle(_ m: BridgeMessage, connection: UUID? = nil, reply: @escaping (Data) -> Void) {
        let now = Date()
        switch m {
        case .ping:
            let r = PingReply(ok: true, version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
                              profile: features.profile.rawValue)
            if var d = try? JSONEncoder().encode(r) { d.append(0x0A); reply(d) }
        case let .activityStart(id, title, subtitle, progress, url):
            center.upsert(Activity(id: "script-\(id)", kind: .script, priority: .p2, state: .running,
                                   symbol: "chevron.left.forwardslash.chevron.right", label: title,
                                   value: progress.map { "\(Int($0 * 100))%" } ?? "", detail: subtitle ?? title,
                                   genericDetail: L("generic.script"), progress: progress, url: url, startedAt: now))
        case let .activityUpdate(id, title, subtitle, progress):
            guard var a = center.activities["script-\(id)"] else { break }
            if let title { a.label = title }
            if let subtitle { a.detail = subtitle }
            if let progress { a.progress = progress; a.value = "\(Int(progress * 100))%" }
            a.updatedAt = now
            center.upsert(a)
        case let .activityEnd(id, success, detail):
            let key = "script-\(id)"
            if center.activities[key] == nil {
                center.upsert(Activity(id: key, kind: .script, priority: .p2, state: .running, symbol: "terminal",
                                       label: id, genericDetail: L("generic.script"), startedAt: now))
            }
            let label = center.activities[key]?.label ?? id
            // Right ear only fits short results ("48s", "exit 1"); longer details go to Peek.
            center.finish(key, success: success, value: detail.flatMap { $0.count <= 10 ? $0 : nil } ?? "",
                          detail: [label, detail].compactMap { $0 }.joined(separator: " · "), now: now)
        case let .notify(title, body):
            center.post(Activity(id: "notify-\(UUID().uuidString)", kind: .notify, priority: .p1, state: .info,
                                 symbol: "bell.badge", label: TextRules.truncateTail(title, max: 12), value: "",
                                 detail: [title, body].compactMap { $0 }.joined(separator: " · "),
                                 genericDetail: L("generic.notify"), startedAt: now), now: now)
        case let .shellStart(pid, cmd, cwd, app, seq):
            guard features.isEnabled(.commands) else { break }
            noteRepo(cwd)
            // A new command replaces the shell's running one; results of earlier commands keep their hold time.
            if let old = commands.running[pid] { center.remove(Self.commandKey(old), now: now) }
            commands.start(shellPid: pid, command: cmd, cwd: cwd, app: app, seq: seq, now: now)
        case let .shellEnd(pid, status, seq):
            guard features.isEnabled(.commands) else { break }
            guard let running = commands.running[pid] else { _ = commands.end(shellPid: pid, status: status, seq: seq, now: now); break }
            let key = Self.commandKey(running)
            guard let f = commands.end(shellPid: pid, status: status, seq: seq, now: now) else {
                if commands.running[pid] == nil { center.remove(key, now: now) }   // too short to show
                break
            }
            let frontmost = f.running.app != nil && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == f.running.app
            guard commands.filter.shouldShowResult(duration: f.duration, terminalFrontmost: frontmost, always: commandResultsAlways)
            else { center.remove(key, now: now); break }
            if center.activities[key] == nil { center.upsert(commandActivity(f.running)) }
            let name = TextRules.commandShortName(f.running.command)
            let d = DurationFormat.result(f.duration)
            center.finish(key, success: status == 0, value: status == 0 ? d : "exit \(status)",
                          detail: status == 0 ? L("command.done", name, d) : L("command.failed", name, status, d), now: now)
        case let .hook(source, env, payload) where source == "codex":
            guard features.isEnabled(.agents), let message = CodexConfig.lastMessage(payload) else { break }
            let project = payload["cwd"]?.string.map { ProjectName.resolve(cwd: $0) } ?? "Codex"
            center.post(Activity(id: "codex-\(payload["turn-id"]?.string ?? UUID().uuidString)", kind: .agent, priority: .p1, state: .success,
                                 symbol: "checkmark", label: L("compact.done"), value: "Codex",
                                 detail: L("codex.done", project) + " · " + TextRules.firstSentence(message),
                                 genericDetail: L("generic.agentDone"), url: env["__CFBundleIdentifier"].map { "app:" + $0 }, startedAt: now), now: now)
        case let .hook(source, env, payload):
            guard ["claude", "cursor", "opencode"].contains(source), features.isEnabled(.agents),
                  let e = ClaudeHookEvent(payload: payload) else { break }
            applyAgentEvent(e, env: env, now: now)
        case let .permissionAsk(requestID, _, env, payload):
            handlePermissionAsk(requestID: requestID, env: env, payload: payload, connection: connection, now: now) { r in
                if var d = try? JSONEncoder().encode(r) { d.append(0x0A); reply(d) }
            }
        case let .shelfAdd(paths):
            guard features.isEnabled(.shelf) else { break }
            ShelfProvider.shared.add(paths.map { URL(fileURLWithPath: $0) })
        case .debugState:
            let state: [String: Any] = [
                "notch": NotchRootView.displayState(self).rawValue,
                "slots": center.slots(fullscreen: fullscreen).map(\.id),
                "activities": center.ordered.map { ["id": $0.id, "kind": $0.kind.rawValue, "priority": $0.priority.rawValue,
                                                    "state": "\($0.state)", "label": $0.label, "value": $0.value, "detail": displayDetail($0)] },
                "sessions": agents.ordered.map { ["project": $0.project, "status": "\($0.status)"] },
                "history": center.history.count,
                "accessibility": AXIsProcessTrusted(),
                "location": CLLocationManager().authorizationStatus.rawValue,
                "media": media.map { ["source": $0.source.rawValue, "title": $0.title, "playing": $0.isPlaying, "app": $0.sourceName] as [String: Any] } ?? [:],
                "visualizerLive": VisualizerProvider.shared.live,
                "lockScreenUnavailable": LockScreenProvider.shared.unavailable,
            ]
            if var d = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) { d.append(0x0A); reply(d) }
        }
        refreshAgentActivity(now: now)
        scheduleTick()
    }

    /// kill(pid, 0): ESRCH means the process is gone; EPERM still means it exists.
    nonisolated static func processAlive(_ pid: Int) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid_t(pid), 0) == 0 || errno == EPERM
    }

    /// One activity per command (not per shell), so a result survives the next prompt.
    static func commandKey(_ r: CommandTracker.Running) -> String {
        "cmd-\(r.shellPid)-\(r.seq ?? Int(r.startedAt.timeIntervalSince1970 * 1000))"
    }

    private func commandActivity(_ r: CommandTracker.Running) -> Activity {
        Activity(id: Self.commandKey(r), kind: .command, priority: .p2, state: .running, symbol: "terminal",
                 label: TextRules.commandShortName(r.command), value: "", detail: L("command.running", TextRules.commandShortName(r.command)),
                 genericDetail: L("generic.command"), startedAt: r.startedAt)
    }

    /// Removing a missing id still counts as a write for Observation; skip it.
    func removeIfPresent(_ id: String, now: Date) {
        if center.activities[id] != nil { center.remove(id, now: now) }
    }

    // MARK: Agents (PRD §F3)

    /// Remembers the git root of a working directory (max 10) so GitHub CI knows which repos to watch.
    func noteRepo(_ cwd: String?) {
        guard let cwd, !cwd.isEmpty else { return }
        var url = URL(fileURLWithPath: cwd).standardizedFileURL
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                let root = url.path
                if recentRepos.first != root { recentRepos = Array(([root] + recentRepos.filter { $0 != root }).prefix(10)) }
                return
            }
            url.deleteLastPathComponent()
        }
    }

    private func applyAgentEvent(_ e: ClaudeHookEvent, env: [String: String], now: Date) {
        if e.name == .sessionStart || e.name == .userPromptSubmit { noteRepo(e.cwd) }
        let before = agents.sessions[e.sessionID]?.status
        agents.apply(e, env: env, now: now, projectName: { ProjectName.resolve(cwd: $0) })
        // Tool ran → any notch card for this session is stale (answered in the terminal).
        if e.name == .postToolUse || e.name == .stop || e.name == .userPromptSubmit {
            for p in pending.values where p.sessionID == e.sessionID && (e.name != .postToolUse || e.toolName == nil || p.tool == e.toolName) {
                resolvePermission(p.requestID, .passthrough)
            }
        }
        guard let s = agents.sessions[e.sessionID] else { return }
        if case .done(let duration, let summary) = s.status, before != s.status {
            postAgentResult(s, success: true, duration: duration, summary: summary, now: now)
        } else if case .failed(let message) = s.status, before != s.status {
            postAgentResult(s, success: false, duration: 0, summary: message, now: now)
        }
        if case .needsPermission = s.status, !isNeedsPermission(before) { triggerP0(now: now) }
    }

    private func isNeedsPermission(_ s: AgentSessions.Status?) -> Bool {
        if case .needsPermission = s { return true }
        return false
    }

    private func postAgentResult(_ s: AgentSessions.Session, success: Bool, duration: TimeInterval, summary: String?, now: Date) {
        let id = "agent-result-\(s.id)"
        let d = DurationFormat.result(duration)
        var a = Activity(id: id, kind: .agent, priority: .p1, state: success ? .success : .failure,
                         symbol: success ? "checkmark" : "xmark", label: success ? L("compact.done") : L("compact.error"),
                         value: success ? d : "", detail: Self.named(success ? L("agent.done", s.project, d) : L("agent.failed"), s.agent),
                         genericDetail: Self.named(success ? L("generic.agentDone") : L("agent.failed"), s.agent), url: s.id, startedAt: now)
        a.endedAt = now
        center.post(a, now: now)
        agents.acknowledgeResult(sessionID: s.id)
        guard success, let cwd = s.cwd else { return }
        // `+x −y` from git, off the main thread.
        Task.detached {
            let out = Shell.run("/usr/bin/git", ["-C", cwd, "diff", "--shortstat", "HEAD"])
            await MainActor.run {
                guard let stat = ShortStat.parse(out ?? ""), var a = AppModel.shared.center.activities[id] else { return }
                a.detail = Self.named(L("agent.doneDiff", s.project, d, DurationFormat.diff(added: stat.added, removed: stat.removed)), s.agent)
                if let summary { a.detail += " · " + summary }
                AppModel.shared.center.upsert(a)
            }
        }
    }

    func refreshAgentActivity(now: Date) {
        waitingNotified = waitingNotified.filter { agents.sessions[$0]?.status == .waitingInput }
        let active = agents.active
        guard features.isEnabled(.agents), let first = active.first else { removeIfPresent("agents", now: now); return }
        var a = Activity(id: "agents", kind: .agent, priority: .p2, state: .running, symbol: "sparkle", label: "",
                         startedAt: first.promptStartedAt ?? first.updatedAt, updatedAt: now)
        let permissions = active.filter { isNeedsPermission($0.status) }
        if let p = permissions.first, case .needsPermission(_, let tool, let detail) = p.status {
            a.priority = .p0
            a.state = .needsAction
            a.label = L("compact.permission")
            a.value = active.count > 1 ? "\(permissions.count)" : TextRules.truncateTail(TextRules.commandShortName(detail ?? tool ?? ""), max: 12)
            let what = [tool, detail].compactMap { $0 }.joined(separator: " ")
            a.detail = what.isEmpty ? Self.named(L("agent.needsPermission"), p.agent) + " · " + p.project : what
            a.genericDetail = Self.named(L("generic.agentPermission"), p.agent)
            a.url = p.id
        } else if active.count > 1 {
            a.label = "\(active.count)"
            a.value = L("compact.agents", active.count)
            a.detail = L("agent.many", active.count)
            a.genericDetail = L("generic.agent")
        } else {
            switch first.status {
            case .working(let tool, let detail):
                a.label = tool ?? L("compact.working")
                a.value = detail.map { TextRules.truncateMiddle($0, max: 13) } ?? ""
                a.detail = Self.named(agentSentence(tool: tool, detail: detail), first.agent) + " · " + first.project
                a.genericDetail = Self.named(L("generic.agent"), first.agent)
            case .waitingInput:
                // P1 shows 5 s and goes to history; it does not stay until Claude gets an answer.
                guard !waitingNotified.contains(first.id) else { return }
                waitingNotified.insert(first.id)
                a.priority = .p1
                a.state = .info
                a.label = L("compact.waiting")
                a.detail = Self.named(L("agent.waiting"), first.agent) + " · " + first.project
                a.genericDetail = Self.named(L("agent.waiting"), first.agent)
                a.url = first.id
                center.post(a, now: now)
                return
            default:
                removeIfPresent("agents", now: now); return
            }
            a.url = first.id
        }
        center.upsert(a)
    }

    /// Agent strings name Claude; sessions from other agents (FR-34) get their own name. Brand names are
    /// the same in both languages, so the swap is safe in id and en.
    nonisolated static func named(_ text: String, _ agent: String) -> String {
        agent == "Claude" ? text : text.replacingOccurrences(of: "Claude", with: agent)
    }

    func agentSentence(tool: String?, detail: String?) -> String {
        switch tool {
        case "Edit", "MultiEdit", "Write": return L("agent.editing", detail ?? "")
        case "Read": return L("agent.reading", detail ?? "")
        case "Bash": return L("agent.running", detail ?? "")
        case nil: return L("agent.thinking")
        default: return L("agent.tool", tool!)
        }
    }

    // MARK: Permission from the notch (FR-9)

    private func handlePermissionAsk(requestID: String, env: [String: String], payload: JSONValue, connection: UUID?,
                                     now: Date, reply: @escaping (PermissionReply) -> Void) {
        guard let e = ClaudeHookEvent(payload: payload), features.isEnabled(.agents) else { reply(.init(decision: .passthrough)); return }
        applyAgentEvent(e, env: env, now: now)
        let session = agents.sessions[e.sessionID]
        let terminalFront = session?.appBundleID != nil && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == session?.appBundleID
        // Never hold the terminal prompt when the user could answer it right there (PRD §F3 step 2).
        guard answerPermissionsFromNotch, !presentationMode, !screenLocked, !terminalFront else {
            reply(.init(decision: .passthrough)); return
        }
        pending[requestID] = PendingPermission(requestID: requestID, sessionID: e.sessionID, tool: e.toolName,
                                               detail: e.toolDetail, createdAt: now, connection: connection, reply: reply)
        agents.setPermission(sessionID: e.sessionID, requestID: requestID, tool: e.toolName, detail: e.toolDetail, now: now)
        let t = Timer(timeInterval: permissionTimeout, repeats: false) { _ in
            MainActor.assumeIsolated { AppModel.shared.resolvePermission(requestID, .passthrough) }
        }
        RunLoop.main.add(t, forMode: .common)
        permissionTimers[requestID] = t
        triggerP0(now: now)
    }

    func resolvePermission(_ requestID: String, _ decision: PermissionDecision) {
        permissionTimers.removeValue(forKey: requestID)?.invalidate()
        guard let p = pending.removeValue(forKey: requestID) else { return }
        p.reply(PermissionReply(decision: decision, message: decision == .deny ? L("permission.deniedMessage") : nil))
        agents.clearPermission(requestID: requestID, now: Date())
        if decision == .allow {
            let a = Activity(id: "perm-ok-\(requestID)", kind: .agent, priority: .p1, state: .success, symbol: "checkmark",
                             label: L("compact.allowed"), detail: L("permission.granted", p.tool ?? ""), startedAt: Date())
            center.post(a, now: Date())
        }
        refreshAgentActivity(now: Date())
    }

    /// The hook process went away (Claude interrupted, prompt answered in the terminal): drop its card.
    func connectionClosed(_ id: UUID) {
        for p in pending.values where p.connection == id {
            permissionTimers.removeValue(forKey: p.requestID)?.invalidate()
            pending[p.requestID] = nil
            agents.clearPermission(requestID: p.requestID, now: Date())
        }
        refreshAgentActivity(now: Date())
    }

    var pendingForDisplay: PendingPermission? { pending.values.sorted { $0.createdAt < $1.createdAt }.first }

    func triggerP0(now: Date) {
        autoPeekUntil = now.addingTimeInterval(4)
        pulse += 1
        if notchState == .closed || notchState == .compact { notchState = .peek }
        if permissionSound { NSSound(named: "Ping")?.play() }
        scheduleTick()
    }

    // MARK: Actions

    func perform(_ action: NotchAction) {
        switch action {
        case .allow(let id): resolvePermission(id, .allow)
        case .deny(let id): resolvePermission(id, .deny)
        case .releaseToTerminal(let id):
            let session = pending[id]?.sessionID
            resolvePermission(id, .passthrough)
            if let session { TerminalFocus.focus(agents.sessions[session]) }
        case .focusSession(let id): TerminalFocus.focus(agents.sessions[id])
        case .join(let url):
            // zoommtg:// needs the Zoom app; fall back to the web link (stored in the meeting's link).
            let web = meetings.first { $0.link?.appURL == url }?.link?.url
            let target = NSWorkspace.shared.urlForApplication(toOpen: url) != nil ? url : (web ?? url)
            if ["https", "http", "zoommtg", "msteams"].contains(target.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(target) }
            if let e = MeetingSchedule.current(meetings, now: Date(), dismissed: dismissedMeetings)?.0 { dismissedMeetings.insert(e.id) }
            refreshMeeting()
        case .openURL(let url):
            // URLs come from scripts over the socket: never open file:// (an .app or .command would run).
            if ["https", "http"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        case .mediaPrevious: MediaProvider.shared.previous()
        case .mediaPlayPause: MediaProvider.shared.playPause()
        case .mediaNext: MediaProvider.shared.next()
        case .dismiss(let id): center.remove(id, now: Date(), toHistory: true)
        case .openStats: selectedTab = .stats; notchState = .expanded
        case .stopProcess(let pid): StatsProvider.shared.stop(pid)
        case .revealFile(let p): NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
        case .shelveFile(let p): ShelfProvider.shared.add([URL(fileURLWithPath: p)])
        case .discordMute: DiscordProvider.shared.toggleMute()
        case .discordDeafen: DiscordProvider.shared.toggleDeaf()
        case .discordLeave: DiscordProvider.shared.leave()
        case .discordKeybindMute: DiscordProvider.shared.sendKeybind(discordMuteKey)
        case .meetingControl(let c): MeetingCallProvider.shared.press(c)
        case .banner(let action, let id): NotificationProvider.shared.perform(action, bannerID: id)
        case .capture(let action, let arg): ScreenshotService.shared.perform(action, arg)
        case .fan(let action): FanProvider.shared.perform(action)
        case .faceUnlockHistory: SettingsWindow.show(section: .faceUnlock)
        case .showUpdate: UpdateWindow.show()
        case .openStorage: StorageWindow.show()
        case .stopRecording: ScreenRecorder.shared.stop()
        case .openDiscord(let u): if u.scheme == "discord" { NSWorkspace.shared.open(u) }
        }
    }

    /// Buttons for an activity in Peek (1–3, design D7).
    func actions(for a: Activity) -> [(String, NotchButton.Kind, NotchAction)] {
        switch a.kind {
        case .agent where a.state == .needsAction:
            if let p = pendingForDisplay {
                return [(L("button.deny"), .normal, .deny(p.requestID)), (L("button.allow"), .primaryAction, .allow(p.requestID)),
                        (L("button.terminal"), .normal, .releaseToTerminal(p.requestID))]
            }
            return [(L("button.openTerminal"), .normal, .focusSession(a.url ?? ""))]
        case .agent:
            return a.url.map { [(L("button.open"), .normal, .focusSession($0))] } ?? []
        case .meeting where a.id == "meeting-live":
            guard let app = MeetingCallProvider.shared.app else { return [] }
            return MeetingControls.Control.allCases.filter { MeetingControls.shortcut(app, $0) != nil }
                .map { (L("meetingControls.\($0.rawValue)"), .normal, .meetingControl($0)) }
        case .meeting:
            return a.url.flatMap(URL.init(string:)).map { [(L("button.join"), .primaryNeutral, .join($0))] } ?? []
        case .discord where a.id == "discord-voice":
            let s = DiscordProvider.shared.state
            return [(s.selfMute ? L("discord.unmute") : L("discord.mute"), .normal, .discordMute),
                    (s.selfDeaf ? L("discord.undeafen") : L("discord.deafen"), .normal, .discordDeafen),
                    (L("discord.leave"), .destructive, .discordLeave)]
        case .discord:
            return [(L("discord.toggleMute"), .normal, .discordKeybindMute)]
        case .capture where a.url?.hasPrefix("capture:") == true:
            let path = String(a.url!.dropFirst(8))
            return [(L("shot.beautify"), .normal, .capture("beautify", path)), (L("shot.save"), .quiet, .capture("save", path)),
                    (L("shot.pin"), .quiet, .capture("pin", path)), (L("shot.text"), .quiet, .capture("text", path))]
        case .capture where a.id == "recording":
            return [(L("rec.stop"), .destructive, .stopRecording)]
        case .capture where a.url?.hasPrefix("saved:") == true:
            return [(L("shot.finder"), .normal, .revealFile(String(a.url!.dropFirst(6))))]
        case .capture where a.url?.hasPrefix("qr:") == true:
            return [(L("button.open"), .normal, .capture("openLink", String(a.url!.dropFirst(3))))]
        case .capture where a.url?.hasPrefix("text:") == true:
            return [(L("shot.showText"), .normal, .capture("showText", String(a.url!.dropFirst(5))))]
        case .notify where a.id == "storage-low":
            return [(L("storage.cleanButton"), .primaryAction, .openStorage)]
        case .notify where a.id == "update":
            return [(L("update.view"), .normal, .showUpdate)]
        case .notify where a.id == "faceunlock":
            return [(L("faceUnlock.history"), .normal, .faceUnlockHistory)]
        case .thermal where a.id == "fan-hot":
            // "Fan max" disappears once the fans are already at max (D47).
            return (a.url == "fan:max" ? [(L("fan.maxButton"), NotchButton.Kind.primaryAction, NotchAction.fan("max"))] : [])
                + [(L("fan.processes"), .normal, .fan("processes"))]
        case .notify where a.url?.hasPrefix("call:") == true:
            let id = String(a.url!.dropFirst(5))
            return [(L("calls.decline"), .destructive, .banner("decline", id)), (L("calls.accept"), .confirm, .banner("accept", id))]
        case .notify where a.url?.hasPrefix("notif:") == true:
            let id = String(a.url!.dropFirst(6))
            var acts: [(String, NotchButton.Kind, NotchAction)] = [(L("button.close"), .quiet, .banner("close", id)), (L("button.open"), .normal, .banner("open", id))]
            if NotificationProvider.shared.banner(id)?.canReply == true, !presentationMode { acts.append((L("notifications.reply"), .normal, .banner("reply", id))) }
            return acts
        case .notify where a.url?.hasPrefix("discord://") == true:
            return a.url.flatMap(URL.init(string:)).map { [(L("button.open"), .normal, .openDiscord($0))] } ?? []
        case .battery where a.priority == .p0:
            return [(L("button.dismiss"), .normal, .dismiss(a.id))]
        case .notify where a.url?.hasPrefix("dl:") == true:
            let path = String(a.url!.dropFirst(3))
            var acts: [(String, NotchButton.Kind, NotchAction)] = [(L("downloads.show"), .normal, .revealFile(path))]
            if features.isEnabled(.shelf) { acts.append((L("downloads.toShelf"), .normal, .shelveFile(path))) }
            return acts
        case .notify where a.url?.hasPrefix("pid:") == true:
            return [(L("stats.view"), .normal, .openStats), (L("stats.stop"), .destructive, .stopProcess(Int32(a.url!.dropFirst(4)) ?? 0))]
        case .script, .notify, .port, .ci:
            return a.url.flatMap(URL.init(string:)).map { [(L("button.open"), .normal, .openURL($0))] } ?? []
        default:
            return []
        }
    }

    /// Menu-bar dot and temperature (D46) follow the fans.
    func fanChanged() { (NSApp.delegate as? AppDelegate)?.refreshStatusItem() }

    // MARK: Presentation Mode (PRD §F12)

    func togglePresentation() {
        presentationMode.toggle()
        if presentationMode {
            for id in pending.keys { resolvePermission(id, .passthrough) }
            let now = Date()
            center.post(Activity(id: "presentation", kind: .presentation, priority: .p1, state: .info, symbol: "eye.slash",
                                 label: L("compact.presentation"), detail: L("presentation.on"), startedAt: now), now: now)
            scheduleTick()
        }
    }

    /// Kinds whose labels/details can carry file names, commands, script titles or meeting titles (PRD §F12).
    /// Port and CI values carry project, branch and workflow names.
    static let sensitiveKinds: Set<ActivityKind> = [.agent, .command, .script, .notify, .meeting, .discord, .port, .ci]

    /// FR-67: without RPC, show "Discord is using the microphone" with a keybind toggle.
    func refreshDiscordSimple() {
        let now = Date()
        let on = features.isEnabled(.discord) && discordClientID.isEmpty && micApp == "Discord"
        if on, center.activities["discord-simple"] == nil {
            center.upsert(Activity(id: "discord-simple", kind: .discord, priority: .p2, state: .running, symbol: "mic.fill",
                                   label: "Discord", value: "", detail: L("discord.simple"), genericDetail: L("discord.voiceGeneric"), startedAt: now))
        } else if !on, center.activities["discord-simple"] != nil {
            center.remove("discord-simple", now: now)
        }
    }

    func displayDetail(_ a: Activity) -> String {
        guard presentationMode else { return a.detail }
        if let g = a.genericDetail { return g }
        switch a.kind {
        case .agent: return L("generic.agent")
        case .command: return L("generic.command")
        case .script: return L("generic.script")
        case .notify: return L("generic.notify")
        case .meeting: return L("generic.meeting")
        default: return a.detail
        }
    }

    /// In Presentation Mode only durations, counts and exit codes survive ("4m 12s", "64%", "exit 1").
    func displayValue(_ a: Activity) -> String {
        guard presentationMode, Self.sensitiveKinds.contains(a.kind) else { return a.value }
        return Self.isNeutralValue(a.value) ? a.value : ""
    }

    nonisolated static func isNeutralValue(_ v: String) -> Bool {
        v.range(of: #"^(exit )?[0-9:.,%hms ]*$"#, options: .regularExpression) != nil
    }

    func displayLabel(_ a: Activity) -> String {
        guard presentationMode, Self.sensitiveKinds.contains(a.kind) else { return a.label }
        switch a.kind {
        case .agent where a.state == .running: return L("compact.working")
        case .agent: return a.label   // "Izin", "Selesai", "Error": generic already
        case .meeting: return L("compact.meeting")
        case .notify: return L("generic.notify")
        case .port, .ci: return a.label   // ":5173", "CI"
        default: return ""            // command & script titles can be anything
        }
    }

    // MARK: Meetings (PRD §F6)

    func refreshMeeting(now: Date = Date()) {
        guard features.isEnabled(.meeting), let (e, phase) = MeetingSchedule.current(meetings, now: now, dismissed: dismissedMeetings) else {
            removeIfPresent("meeting", now: now); return
        }
        let wasImminent = center.activities["meeting"]?.priority == .p0
        var a = Activity(id: "meeting", kind: .meeting, priority: phase == .imminent ? .p0 : .p1,
                         state: phase == .imminent ? .needsAction : .info, symbol: "calendar",
                         label: TextRules.truncateTail(e.title, max: 10), value: DurationFormat.countdown(e.start.timeIntervalSince(now)),
                         detail: phase == .imminent ? L("meeting.imminent", e.title)
                                                     : L("meeting.soon", e.title, Int((e.start.timeIntervalSince(now) / 60).rounded(.up))),
                         genericDetail: L("generic.meeting"), url: (e.link?.appURL ?? e.link?.url)?.absoluteString,
                         startedAt: e.start.addingTimeInterval(-MeetingSchedule.soonWindow), updatedAt: now)
        // Called every tick: only write when something visible changed, so the notch does not re-render each second.
        if let old = center.activities["meeting"] {
            a.updatedAt = old.updatedAt
            if old == a { return }
        }
        center.upsert(a)
        if phase == .imminent && !wasImminent { triggerP0(now: now) }
    }

    var nextMeetingToday: MeetingSchedule.Event? {
        meetings.filter { !$0.isAllDay && $0.end > Date() }.sorted { $0.start < $1.start }.first
    }

    // MARK: Timer (PRD §F7)

    func startTimer(_ t: CountdownTimer) {
        timer = t
        refreshTimerActivity(now: Date())
        scheduleTick()
    }

    func stopTimer() {
        timer = nil
        center.remove("timer", now: Date())
    }

    func toggleTimerPause() {
        let now = Date()
        if timer?.isPaused == true { timer?.resume(now: now) } else { timer?.pause(now: now) }
        refreshTimerActivity(now: now)
    }

    private func refreshTimerActivity(now: Date) {
        guard let t = timer, features.isEnabled(.timer) else { return }
        let label = t.phase == .timer ? L("timer.timer") : (t.phase == .focus ? L("timer.focus") : L("timer.break"))
        let a = Activity(id: "timer", kind: .timer, priority: .p2, state: .running, symbol: "timer", label: label,
                         value: DurationFormat.running(t.remaining(now: now)), detail: label,
                         progress: (t.progress(now: now) * 100).rounded() / 100,
                         startedAt: center.activities["timer"]?.startedAt ?? now,
                         updatedAt: center.activities["timer"]?.updatedAt ?? now)
        if center.activities["timer"] != a { center.upsert(a) }
    }

    private func timerFinished(now: Date) {
        guard let t = timer else { return }
        removeIfPresent("timer", now: now)
        let msg = t.phase == .focus ? L("timer.focusDone") : (t.phase == .timer ? L("timer.done") : L("timer.breakDone"))
        center.post(Activity(id: "timer-done-\(now.timeIntervalSince1970)", kind: .timer, priority: .p1, state: .success,
                             symbol: "timer", label: L("timer.timer"), detail: msg, startedAt: now), now: now)
        NSSound(named: "Glass")?.play()
        timer = t.next(now: now)
        if timer != nil { refreshTimerActivity(now: now) }
    }

    // MARK: Battery (FR-70)

    func batteryChanged(_ new: BatterySnapshot) {
        let old = battery
        battery = new
        guard features.isEnabled(.battery) else { return }
        let now = Date()
        for e in BatteryLogic.events(from: old, to: new) {
            var a = Activity(id: "battery", kind: .battery, priority: .p1, state: .info, symbol: "bolt.fill",
                             label: "", value: "\(new.percent)%", detail: "", startedAt: now)
            switch e {
            case .pluggedIn:
                a.state = .success
                a.detail = new.minutesToFull.map { L("battery.chargingFull", new.percent, DurationFormat.long(TimeInterval($0 * 60), language: L10n.language)) }
                    ?? L("battery.charging", new.percent)
            case .unplugged:
                a.symbol = "battery.75percent"; a.detail = L("battery.unplugged", new.percent)
            case .full:
                a.state = .success; a.value = L("battery.fullShort"); a.detail = L("battery.full")
            case .low20:
                a.state = .needsAction; a.symbol = "battery.25percent"; a.detail = L("battery.low", new.percent)
            case .low10:
                a.priority = .p0; a.state = .failure; a.symbol = "battery.0percent"; a.detail = L("battery.low10", new.percent)
            }
            center.post(a, now: now)
            if a.priority == .p0 { triggerP0(now: now) }
        }
        scheduleTick()
    }

    // MARK: Media (PRD §F5)

    func mediaChanged(_ m: MediaState?) {
        let artworkChanged = m?.artworkKey != media?.artworkKey || (media?.artwork == nil && m?.artwork != nil)
        media = m
        if artworkChanged { mediaAccent = accentFromArtwork ? DY.accent(m?.artwork) : DY.fg }
        LyricsProvider.shared.trackChanged(m)
        let now = Date()
        guard features.isEnabled(.media), let m, m.isPlaying else { removeIfPresent("media", now: now); return }
        center.upsert(Activity(id: "media", kind: .media, priority: .p3, state: .ambient, symbol: "music.note",
                               label: m.title, value: "", detail: "\(m.title) · \(m.artist)", startedAt: now,
                               updatedAt: center.activities["media"]?.updatedAt ?? now))
    }
}
