import AppKit
import DylanCore

/// Finds a CLI tool: GUI apps do not inherit the shell's PATH.
enum Tool {
    nonisolated static func path(_ name: String) -> String? {
        ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"].map { "\($0)/\(name)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// Docker (FR-33), GitHub Actions & reviews (FR-30) and script widgets (FR-31) for the Dev tab. [Dev] only.
@Observable
final class DevIntegrations {
    static let shared = DevIntegrations()

    var containers: [DockerPS.Container] = []
    var dockerAvailable = Tool.path("docker") != nil
    var runs: [(repo: String, run: GitHubCI.Run)] = []
    var reviewRequests: Int?
    var widgets: [String: ScriptWidget.Output] = [:]
    var widgetErrors: [String: String] = [:]

    @ObservationIgnored private var dockerTimer: Timer?
    @ObservationIgnored private var githubTimer: Timer?
    @ObservationIgnored private var widgetTimers: [String: Timer] = [:]
    @ObservationIgnored private var lastStates: [Int: GitHubCI.Run.State] = [:]
    @ObservationIgnored private var firstGitHubPoll = true

    // MARK: Docker (only while the Dev tab is open)

    func devTabVisible(_ visible: Bool) {
        dockerTimer?.invalidate(); dockerTimer = nil
        guard visible, AppModel.shared.features.isEnabled(.docker), dockerAvailable else { return }
        refreshDocker()
        let t = Timer(timeInterval: 10, repeats: true) { _ in MainActor.assumeIsolated { DevIntegrations.shared.refreshDocker() } }
        RunLoop.main.add(t, forMode: .common)
        dockerTimer = t
    }

    func refreshDocker() {
        guard let docker = Tool.path("docker") else { dockerAvailable = false; return }
        Task.detached {
            let out = Shell.run(docker, ["ps", "-a", "--format", "{{json .}}"], timeout: 8)
            await MainActor.run {
                DevIntegrations.shared.dockerAvailable = out != nil
                DevIntegrations.shared.containers = DockerPS.parse(out ?? "")
            }
        }
    }

    func docker(_ verb: String, _ c: DockerPS.Container) {
        guard let docker = Tool.path("docker"), ["restart", "stop", "start"].contains(verb) else { return }
        Task.detached {
            _ = Shell.run(docker, [verb, c.id], timeout: 30)
            await MainActor.run { DevIntegrations.shared.refreshDocker() }
        }
    }

    /// Opens Terminal with `docker logs -f` (a generated .command file, container name shell-quoted).
    func dockerLogs(_ c: DockerPS.Container) {
        guard let docker = Tool.path("docker") else { return }
        let q = "'" + c.name.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dylan-logs-\(c.id.prefix(12)).command")
        try? "#!/bin/sh\nexec \(docker) logs -f --tail 200 \(q)\n".write(to: file, atomically: true, encoding: .utf8)
        chmod(file.path, 0o700)
        NSWorkspace.shared.open(file)
    }

    // MARK: GitHub (opt-in; uses the existing `gh` login)

    func startGitHub() {
        guard githubTimer == nil else { return }
        pollGitHub()
    }

    func stopGitHub() {
        githubTimer?.invalidate(); githubTimer = nil; runs = []; reviewRequests = nil
        firstGitHubPoll = true; lastStates = [:]
        AppModel.shared.removeIfPresent("ci-running", now: Date())
    }

    private func schedule(_ interval: TimeInterval) {
        githubTimer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: false) { _ in MainActor.assumeIsolated { DevIntegrations.shared.pollGitHub() } }
        t.tolerance = interval / 10
        RunLoop.main.add(t, forMode: .common)
        githubTimer = t
    }

    func pollGitHub() {
        guard AppModel.shared.features.isEnabled(.github), let gh = Tool.path("gh") else { return }
        let roots = AppModel.shared.recentRepos
        Task.detached {
            var all: [(String, GitHubCI.Run)] = []
            for root in roots {
                guard let remote = Shell.run("/usr/bin/git", ["-C", root, "remote", "get-url", "origin"]),
                      let repo = GitHubCI.repo(fromRemote: remote),
                      let branch = Shell.run("/usr/bin/git", ["-C", root, "rev-parse", "--abbrev-ref", "HEAD"])?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty else { continue }
                let out = Shell.run(gh, ["run", "list", "-R", repo, "--branch", branch, "--limit", "3", "--json", GitHubCI.runFields], timeout: 15)
                for r in GitHubCI.parseRuns(Data((out ?? "[]").utf8)) { all.append((repo, r)) }
            }
            let reviews = Shell.run(gh, ["api", "-X", "GET", "search/issues", "-f", "q=is:pr is:open review-requested:@me", "--jq", ".total_count"], timeout: 15)
                .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let result = all
            await MainActor.run { DevIntegrations.shared.gitHubPolled(result, reviews: reviews) }
        }
    }

    private func gitHubPolled(_ list: [(String, GitHubCI.Run)], reviews: Int?) {
        // A poll that was in flight when GitHub was turned off.
        guard AppModel.shared.features.isEnabled(.github) else { return }
        runs = list.map { (repo: $0.0, run: $0.1) }
        reviewRequests = reviews
        let m = AppModel.shared
        let now = Date()
        if !firstGitHubPoll {
            for r in GitHubCI.newFailures(previous: lastStates, current: list.map(\.1)) {
                let repo = list.first { $0.1.id == r.id }?.0 ?? ""
                m.center.post(Activity(id: "ci-\(r.id)", kind: .ci, priority: .p1, state: .failure, symbol: "xmark",
                                       label: "CI", value: TextRules.truncateTail(r.name, max: 10),
                                       detail: L("ci.failed", r.name, r.branch) + " · " + repo, genericDetail: L("ci.failedGeneric"),
                                       url: r.url, startedAt: now), now: now)
            }
        }
        firstGitHubPoll = false
        lastStates = Dictionary(list.map { ($0.1.id, $0.1.state) }, uniquingKeysWith: { a, _ in a })
        // A running run on the active branch is a P2 activity.
        if let r = list.first(where: { $0.1.state == .running }) {
            m.center.upsert(Activity(id: "ci-running", kind: .ci, priority: .p2, state: .running, symbol: "arrow.triangle.branch",
                                     label: "CI", value: TextRules.truncateTail(r.1.branch, max: 12), detail: L("ci.running", r.1.name, r.1.branch),
                                     genericDetail: L("ci.runningGeneric"), url: r.1.url, startedAt: r.1.startedAt ?? now,
                                     updatedAt: m.center.activities["ci-running"]?.updatedAt ?? now))
        } else if m.center.activities["ci-running"] != nil {
            m.center.remove("ci-running", now: now)
        }
        m.scheduleTick()
        schedule(GitHubCI.interval(list.map(\.1)))
    }

    // MARK: Script widgets

    static var widgetDir: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/dylan/widgets") }

    func startWidgets() {
        stopWidgets()
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: Self.widgetDir.path) else { return }
        for n in names.sorted() where !n.hasPrefix(".") {
            let path = Self.widgetDir.appendingPathComponent(n).path
            guard fm.isExecutableFile(atPath: path) else { continue }
            let interval = ScriptWidget.interval(fromScript: (try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
            runWidget(path)
            let t = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { DevIntegrations.shared.runWidget(path) } }
            t.tolerance = interval / 10
            RunLoop.main.add(t, forMode: .common)
            widgetTimers[path] = t
        }
    }

    func stopWidgets() {
        widgetTimers.values.forEach { $0.invalidate() }
        for path in widgetTimers.keys { AppModel.shared.removeIfPresent("widget-\(path)", now: Date()) }
        widgetTimers = [:]
        widgets = [:]
        widgetErrors = [:]
    }

    /// Runs with the user's login shell so PATH matches their terminal; 10 s timeout.
    func runWidget(_ path: String) {
        Task.detached {
            let out = Shell.run("/bin/zsh", ["-lc", "exec \"$0\"", path], timeout: 10)
            let parsed = out.flatMap { ScriptWidget.parse(Data($0.utf8)) }
            await MainActor.run { DevIntegrations.shared.widgetRan(path, parsed, failed: out == nil) }
        }
    }

    private func widgetRan(_ path: String, _ o: ScriptWidget.Output?, failed: Bool) {
        let id = "widget-\(path)"
        let m = AppModel.shared
        guard widgetTimers[path] != nil else { return }   // stopped or removed while it ran
        guard let o else {
            widgets[path] = nil
            widgetErrors[path] = failed ? L("widgets.timeout") : L("widgets.badJSON")
            return
        }
        widgetErrors[path] = nil
        widgets[path] = o
        let now = Date()
        if o.activity {
            m.center.upsert(Activity(id: id, kind: .script, priority: o.state == .error ? .p1 : .p2,
                                     state: o.state == .error ? .failure : (o.state == .running ? .running : .info),
                                     symbol: "square.grid.2x2", label: TextRules.truncateTail(o.title, max: 10), value: o.value,
                                     detail: "\(o.title) · \(o.value)", genericDetail: L("generic.script"), progress: o.progress, url: o.url,
                                     startedAt: m.center.activities[id]?.startedAt ?? now, updatedAt: now))
        } else if m.center.activities[id] != nil {
            m.center.remove(id, now: now)
        }
        m.scheduleTick()
    }
}
