import AppKit
import DylanCore
import SMCKit
import SwiftUI

/// `Dylan --snapshot <dir> [--lang id|en]`: renders notch states to PNG without Screen Recording
/// (PRD Bagian 4 debug tools). Used for visual review and to check text length in both languages.
enum Snapshot {
    /// Views that use AppKit layers draw a static SwiftUI stand-in while this is set.
    static var rendering = false
    nonisolated(unsafe) static var studioSample = false
    nonisolated(unsafe) static var enrollStep: Int?

    static func render(to dir: URL) {
        rendering = true
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "io.github.ramdanegie.dylan.snapshot"
        AppModel.store = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let m = AppModel.shared
        let g = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32, leftAuxWidth: 656, rightAuxWidth: 656)
        let now = Date()
        let lang = L10n.language
        m.features.profile = .developer
        m.features.toggles = [:]

        func reset() {
            m.center = ActivityCenter()
            m.agents = AgentSessions()
            m.pending = [:]
            m.media = nil
            m.timer = nil
            m.notchState = .closed
            m.presentationMode = false
            m.cameraOn = false; m.micOn = false
            m.selectedTab = .home
        }

        func agentWorking() {
            let env = ["__CFBundleIdentifier": "com.microsoft.VSCode", "TERM_PROGRAM": "vscode"]
            for p in [#"{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/Users/gg/dev/api-gateway"}"#,
                      #"{"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/Users/gg/dev/api-gateway","tool_name":"Edit","tool_input":{"file_path":"/x/AuthService.swift"}}"#] {
                m.handle(.hook(source: "claude", env: env, payload: try! JSONDecoder().decode(JSONValue.self, from: Data(p.utf8)))) { _ in }
            }
            if var a = m.center.activities["agents"] { a.startedAt = now.addingTimeInterval(-161); m.center.upsert(a) }
        }

        func music() {
            var s = MediaState(source: .spotify, title: "Sore di Kemang", artist: "Arsa", album: "Senja di Selatan",
                               isPlaying: true, position: 102, duration: 238, positionAt: now)
            s.artwork = sampleArtwork(); s.artworkKey = "x"; s.volume = 60
            m.mediaChanged(s)
        }

        let cases: [(String, () -> Void)] = [
            ("D2-closed", {}),
            ("D3-agent-working", { agentWorking(); m.notchState = .compact }),
            ("D3-agent-permission", {
                agentWorking()
                m.handle(.hook(source: "claude", env: [:], payload: try! JSONDecoder().decode(JSONValue.self, from: Data(
                    #"{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"Bash","tool_input":{"command":"npm install zod"}}"#.utf8)))) { _ in }
                m.notchState = .compact
            }),
            ("D3-agent-done", {
                m.center.post(Activity(id: "r", kind: .agent, priority: .p1, state: .success, symbol: "checkmark", label: L("compact.done"),
                                       value: "4m 12s", detail: L("agent.doneDiff", "telekonsul-ios", "4m 12s", "+120 \u{2212}8"), startedAt: now), now: now)
                m.notchState = .compact
            }),
            ("D4-command-running", {
                m.center.upsert(Activity(id: "cmd-1", kind: .command, priority: .p2, state: .running, symbol: "terminal", label: "npm test",
                                         detail: L("command.running", "npm test"), startedAt: now.addingTimeInterval(-83)))
                m.notchState = .compact
            }),
            ("D4-command-failed", {
                m.center.upsert(Activity(id: "cmd-1", kind: .command, priority: .p2, state: .running, symbol: "terminal", label: "npm test", startedAt: now))
                m.center.finish("cmd-1", success: false, value: "exit 1", detail: L("command.failed", "npm test", 1, "2m 13s"), now: now)
                m.notchState = .compact
            }),
            ("D5-now-playing", { music(); m.notchState = .compact }),
            ("D5-timer", { m.startTimer(.pomodoro(now: now.addingTimeInterval(-378))); m.notchState = .compact }),
            ("D6-duo-agent-music", { agentWorking(); music(); m.notchState = .compact }),
            ("D7-peek-permission", {
                agentWorking()
                m.handle(.hook(source: "claude", env: [:], payload: try! JSONDecoder().decode(JSONValue.self, from: Data(
                    #"{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"Bash","tool_input":{"command":"npm install zod"}}"#.utf8)))) { _ in }
                m.pending["r1"] = PendingPermission(requestID: "r1", sessionID: "s1", tool: "Bash", detail: "npm install zod", createdAt: now) { _ in }
                m.notchState = .peek
            }),
            ("D7-peek-agent", { agentWorking(); m.notchState = .peek }),
            ("D7-peek-music", { music(); m.notchState = .peek }),
            ("D8-expanded-home", { music(); m.startTimer(.pomodoro(now: now.addingTimeInterval(-378))); agentWorking(); m.notchState = .expanded }),
            ("D23-expanded-media", { music(); m.selectedTab = .media; m.notchState = .expanded }),
            ("D9-expanded-agents", { agentWorking(); m.selectedTab = .agents; m.notchState = .expanded }),
            ("D44-studio", { Snapshot.studioSample = true }),
            ("D21-face-compact", {
                m.center.post(Activity(id: "faceunlock", kind: .notify, priority: .p1, state: .success, symbol: "faceid", label: L("faceUnlock.short"),
                                       value: "09.12", detail: L("faceUnlock.unlockedDetail", "09.12", "18 m"), progress: 0.93, url: "faceunlock:history", startedAt: now), now: now)
                m.notchState = .compact
            }),
            ("D21-face-peek", {
                m.center.post(Activity(id: "faceunlock", kind: .notify, priority: .p1, state: .success, symbol: "faceid", label: L("faceUnlock.short"),
                                       value: "09.12", detail: L("faceUnlock.unlockedDetail", "09.12", "18 m"), progress: 0.93, url: "faceunlock:history", startedAt: now), now: now)
                m.notchState = .peek
            }),
            ("D21-face-off", {
                m.center.post(Activity(id: "faceunlock", kind: .notify, priority: .p1, state: .failure, symbol: "xmark", label: L("faceUnlock.short"),
                                       value: L("faceUnlock.off"), detail: L("faceUnlock.offTooMany"), url: "faceunlock:history", startedAt: now), now: now)
                m.notchState = .peek
            }),
            ("whats-new", {}),
            ("D19-enroll-1", { Snapshot.enrollStep = 0 }),
            ("D19-enroll-3", { Snapshot.enrollStep = 2 }),
            ("D19-enroll-4", { Snapshot.enrollStep = 3 }),
            ("D45-thermal", {
                let f = FanProvider.shared
                f.fans = [SMC.Fan(index: 0, rpm: 3240, min: 1200, max: 5779, manual: false, target: 3240),
                          SMC.Fan(index: 1, rpm: 3480, min: 1200, max: 6241, manual: false, target: 3480)]
                f.temps = [.cpu: 72, .gpu: 63, .ssd: 44, .battery: 33]
                f.cpuHistory = (0..<40).map { (i: Int) -> Double in let t = Double(i); return 68 + 9 * sin(t / 6) + 4 * sin(t / 2.3) }
                m.selectedTab = .thermal; m.notchState = .expanded
            }),
            ("D47-fan-hot", {
                m.center.post(Activity(id: "fan-hot", kind: .thermal, priority: .p1, state: .needsAction, symbol: "thermometer.high",
                                       label: "97°", value: "5.800 rpm", detail: L("fan.hotBy", "Xcode", 380), genericDetail: L("fan.hot"),
                                       url: "fan:max", startedAt: now), now: now)
                m.notchState = .peek
            }),
            ("FR41-terminal", {
                m.features.toggles[.terminal] = true
                TerminalProvider.shared.lines = ["~/web-admin % git status -sb", "## feat/login...origin/feat/login [ahead 2]",
                                                 " M src/AuthService.ts", "?? src/login.test.ts", "~/web-admin % npm test", "", "  ✓ 42 passed (1.8s)", "~/web-admin % "]
                m.selectedTab = .terminal; m.notchState = .expanded
            }),
            ("D14-presentation", { agentWorking(); m.presentationMode = true; m.notchState = .compact }),
            ("D14-presentation-script", {
                m.handle(.activityStart(id: "d", title: "deploy client-x", subtitle: "prod", progress: 0.4, url: nil)) { _ in }
                m.handle(.hook(source: "claude", env: [:], payload: try! JSONDecoder().decode(JSONValue.self, from: Data(
                    #"{"hook_event_name":"PermissionRequest","session_id":"s9","tool_name":"Bash","tool_input":{"command":"cat secret-client.env"}}"#.utf8)))) { _ in }
                m.presentationMode = true; m.notchState = .peek
            }),
            ("D30-charging", {
                m.center.post(Activity(id: "battery", kind: .battery, priority: .p1, state: .success, symbol: "bolt.fill", label: "",
                                       value: "64%", detail: L("battery.chargingFull", 64, DurationFormat.long(4800, language: lang)), startedAt: now), now: now)
                m.notchState = .peek
            }),
            ("D32-privacy-dots", { m.cameraOn = true; m.micOn = true; m.notchState = .compact }),
        ]

        for (name, setup) in cases {
            reset()
            setup()
            let layout = NotchLayout(g)
            let view = NotchRootView(layout: layout)
                .environment(\.colorScheme, .dark)
                .frame(width: g.panelFrame.width, height: g.panelFrame.height)
                .background(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.7)], startPoint: .top, endPoint: .bottom))
                .transaction { $0.animation = nil }
            if name == "whats-new" {
                // The bundled CHANGELOG is not next to a bare binary; read the repo copy.
                let md = (try? String(contentsOfFile: lang == "id" ? "CHANGELOG.id.md" : "CHANGELOG.md", encoding: .utf8)) ?? ""
                let r = ImageRenderer(content: ChangelogText(markdown: Changelog.section(md, version: "0.1.2") ?? "").padding(20)
                    .frame(width: 480, alignment: .topLeading).background(Color(nsColor: .windowBackgroundColor)))
                r.scale = 2
                if let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                    try? png.write(to: dir.appendingPathComponent("\(name)-\(lang).png"))
                    print("✓ \(name)-\(lang).png")
                }
                continue
            }
            if let step = Snapshot.enrollStep {
                Snapshot.enrollStep = nil
                let r = ImageRenderer(content: FaceEnrollView(done: {}, step: step).background(Color(nsColor: .windowBackgroundColor)))
                r.scale = 2
                if let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                    try? png.write(to: dir.appendingPathComponent("\(name)-\(lang).png"))
                    print("✓ \(name)-\(lang).png")
                }
                continue
            }
            if Snapshot.studioSample {
                // Studio on a sample "screenshot": the sample notch image itself, framed and beautified.
                Snapshot.studioSample = false
                let sample = ImageRenderer(content: NotchRootView(layout: layout).environment(\.colorScheme, .dark)
                    .frame(width: 760, height: 400).background(Color(white: 0.96)))
                sample.scale = 2
                if let cg = sample.cgImage {
                    let model = StudioModel(original: cg, url: URL(fileURLWithPath: "/tmp/sample.png"))
                    model.frame = .browser; model.background = 0; model.shadow = 2; model.layout = 0; model.padding = 64; model.zoom = 100
                    model.count = 1; model.ratio = 0
                    model.add(Mark(kind: .arrow, a: CGPoint(x: 0.15, y: 0.75), b: CGPoint(x: 0.4, y: 0.4), color: .red))
                    model.add(Mark(kind: .number, a: CGPoint(x: 0.12, y: 0.8), b: CGPoint(x: 0.12, y: 0.8), number: 1, color: .red))
                    if let out = model.render(), let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) {
                        try? png.write(to: dir.appendingPathComponent("\(name)-\(lang).png"))
                        print("✓ \(name)-\(lang).png")
                    }
                }
                continue
            }
            let r = ImageRenderer(content: view)
            r.scale = 2
            guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: dir.appendingPathComponent("\(name)-\(lang).png"))
            print("✓ \(name)-\(lang).png")
        }
    }

    /// Orange gradient stand-in for album art (no copyrighted artwork in the repo).
    static func sampleArtwork() -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { r in
            NSGradient(colors: [.systemOrange, .systemPink])?.draw(in: r, angle: 45)
            return true
        }
    }
}
