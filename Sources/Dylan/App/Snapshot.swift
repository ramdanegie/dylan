import AppKit
import DylanCore
import SwiftUI

/// `Dylan --snapshot <dir> [--lang id|en]`: renders notch states to PNG without Screen Recording
/// (PRD Bagian 4 debug tools). Used for visual review and to check text length in both languages.
enum Snapshot {
    static func render(to dir: URL) {
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
