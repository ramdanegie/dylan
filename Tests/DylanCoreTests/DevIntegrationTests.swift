import Foundation
import Testing
@testable import DylanCore

@Suite struct DevIntegrationTests {
    @Test func dockerPS() {
        let out = """
        {"ID":"a1","Names":"redis-cache","Image":"redis:7","State":"exited","Status":"Exited (0) 3 minutes ago"}
        {"ID":"b2","Names":"postgres-dev","Image":"postgres:16","State":"running","Status":"Up 2 hours"}
        not json
        """
        let c = DockerPS.parse(out)
        #expect(c.map(\.name) == ["postgres-dev", "redis-cache"])
        #expect(c[0].running && !c[1].running && c[1].status.hasPrefix("Exited"))
    }

    @Test func githubRuns() {
        let json = #"""
        [{"databaseId":1,"name":"build","headBranch":"feat/login","status":"completed","conclusion":"failure","url":"https://github.com/x/y/actions/runs/1","createdAt":"2026-11-03T02:00:00Z"},
         {"databaseId":2,"name":"test","headBranch":"main","status":"in_progress","conclusion":"","url":"u","createdAt":"2026-11-03T02:01:00Z"},
         {"databaseId":3,"name":"lint","headBranch":"main","status":"completed","conclusion":"success","url":"u","createdAt":"2026-11-03T01:00:00Z"}]
        """#
        let runs = GitHubCI.parseRuns(Data(json.utf8))
        #expect(runs.map(\.state) == [.failure, .running, .success])
        #expect(GitHubCI.interval(runs) == 15)
        #expect(GitHubCI.interval([runs[0]]) == 60)
        #expect(GitHubCI.newFailures(previous: [1: .running], current: runs).map(\.id) == [1])
        #expect(GitHubCI.newFailures(previous: [:], current: runs).isEmpty)          // first poll never alerts
        #expect(GitHubCI.newFailures(previous: [1: .failure], current: runs).isEmpty)
    }

    @Test(arguments: [("https://github.com/ramdanegie/dylan.git", "ramdanegie/dylan"), ("git@github.com:ramdanegie/dylan.git", "ramdanegie/dylan"),
                      ("https://github.com/a/b", "a/b")])
    func remotes(_ url: String, _ repo: String) { #expect(GitHubCI.repo(fromRemote: url) == repo) }

    @Test func nonGitHubRemote() { #expect(GitHubCI.repo(fromRemote: "https://gitlab.com/a/b.git") == nil) }

    @Test func widgets() throws {
        #expect(ScriptWidget.interval(fromScript: "#!/bin/sh\n# dylan: interval=5m\necho") == 300)
        #expect(ScriptWidget.interval(fromScript: "#!/bin/sh\n# dylan: interval=2s") == 5)       // minimum
        #expect(ScriptWidget.interval(fromScript: "echo hi") == 60)
        let o = try #require(ScriptWidget.parse(Data(#"{"title":"k8s prod","value":"12/12 pods","state":"ok","progress":1.4,"url":"https://x","activity":false}"#.utf8)))
        #expect(o.title == "k8s prod" && o.progress == 1 && o.state == .ok)
        #expect(ScriptWidget.parse(Data(#"{"value":"x"}"#.utf8)) == nil)
        #expect(ScriptWidget.parse(Data(#"{"title":"q","value":1200,"state":"WEIRD"}"#.utf8))?.value == "1200")
    }
}

@Suite struct ShellTests {
    @Test func largeOutputDoesNotStall() {
        let out = Shell.run("/bin/sh", ["-c", "head -c 200000 /dev/zero | tr '\\0' a"], timeout: 5)
        #expect(out?.count == 200_000)
    }

    @Test func timeoutAndMissingTool() {
        #expect(Shell.run("/bin/sleep", ["5"], timeout: 0.2) == nil)
        #expect(Shell.run("/nonexistent/tool", []) == nil)
        #expect(Shell.run("/bin/echo", ["hi"]) == "hi\n")
    }
}
