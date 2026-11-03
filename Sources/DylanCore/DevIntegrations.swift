import Foundation

/// Docker containers from `docker ps -a --format '{{json .}}'` (FR-33).
public enum DockerPS {
    public struct Container: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var image: String
        public var running: Bool
        public var status: String   // "Up 2 hours", "Exited (0) 3 minutes ago"
    }

    public static func parse(_ output: String) -> [Container] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            guard let d = line.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let id = o["ID"] as? String else { return nil }
            let state = (o["State"] as? String ?? "").lowercased()
            return Container(id: id, name: (o["Names"] as? String) ?? id, image: o["Image"] as? String ?? "",
                             running: state == "running", status: o["Status"] as? String ?? state)
        }
        .sorted { ($0.running ? 0 : 1, $0.name) < ($1.running ? 0 : 1, $1.name) }
    }
}

/// GitHub Actions runs from `gh run list --json …` and review requests (FR-30).
public enum GitHubCI {
    public struct Run: Equatable, Sendable {
        public enum State: String, Sendable { case running, success, failure, other }
        public var id: Int
        public var name: String
        public var branch: String
        public var state: State
        public var url: String
        public var startedAt: Date?
    }

    public static let runFields = "databaseId,name,headBranch,status,conclusion,url,createdAt"

    public static func parseRuns(_ data: Data) -> [Run] {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        return arr.compactMap { o in
            guard let id = (o["databaseId"] as? NSNumber)?.intValue else { return nil }
            let status = (o["status"] as? String ?? "").lowercased()
            let conclusion = (o["conclusion"] as? String ?? "").lowercased()
            let state: Run.State = ["queued", "in_progress", "waiting", "requested", "pending"].contains(status) ? .running
                : conclusion == "success" ? .success
                : ["failure", "timed_out", "startup_failure"].contains(conclusion) ? .failure : .other
            return Run(id: id, name: o["name"] as? String ?? "CI", branch: o["headBranch"] as? String ?? "",
                       state: state, url: o["url"] as? String ?? "", startedAt: (o["createdAt"] as? String).flatMap(iso.date))
        }
    }

    /// Owner/name from a git remote URL (https or ssh); nil for non-GitHub remotes.
    public static func repo(fromRemote url: String) -> String? {
        let s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = s.range(of: #"github\.com[:/]([^/]+)/([^/]+?)(\.git)?$"#, options: .regularExpression) else { return nil }
        let tail = s[r].replacingOccurrences(of: "github.com", with: "").drop { $0 == ":" || $0 == "/" }
        let parts = tail.replacingOccurrences(of: ".git", with: "").split(separator: "/")
        return parts.count == 2 ? "\(parts[0])/\(parts[1])" : nil
    }

    /// Runs whose state just turned into a failure, compared with the previous poll.
    public static func newFailures(previous: [Int: Run.State], current: [Run]) -> [Run] {
        current.filter { $0.state == .failure && previous[$0.id] != nil && previous[$0.id] != .failure }
    }

    /// Poll interval: 15 s while a run is in progress, 60 s otherwise (PRD §F11).
    public static func interval(_ runs: [Run]) -> TimeInterval { runs.contains { $0.state == .running } ? 15 : 60 }
}

/// Script widgets in ~/.config/dylan/widgets (FR-31, PRD §F11).
public enum ScriptWidget {
    public struct Output: Equatable, Sendable {
        public enum State: String, Sendable { case ok, warn, error, running }
        public var title: String
        public var value: String
        public var state: State
        public var progress: Double?
        public var url: String?
        public var activity: Bool
    }

    /// `# dylan: interval=60s` (also `5m`, `1h`); default 60 s, minimum 5 s.
    public static func interval(fromScript text: String) -> TimeInterval {
        for line in text.split(whereSeparator: \.isNewline).prefix(10) {
            guard let r = line.range(of: #"dylan:\s*interval=(\d+)([smh]?)"#, options: .regularExpression) else { continue }
            let m = String(line[r])
            let num = Double(m.filter(\.isNumber)) ?? 60
            let unit = m.last.map(String.init) ?? "s"
            let secs = unit == "m" ? num * 60 : unit == "h" ? num * 3600 : num
            return max(5, secs)
        }
        return 60
    }

    public static func parse(_ data: Data) -> Output? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let title = o["title"] as? String else { return nil }
        let value: String = (o["value"] as? String) ?? (o["value"] as? NSNumber)?.stringValue ?? ""
        return Output(title: title, value: value, state: Output.State(rawValue: (o["state"] as? String ?? "ok").lowercased()) ?? .ok,
                      progress: (o["progress"] as? NSNumber).map { min(1, max(0, $0.doubleValue)) },
                      url: o["url"] as? String, activity: o["activity"] as? Bool ?? false)
    }
}
