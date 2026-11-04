import Foundation
import Testing
@testable import DylanCore

@Suite struct UpdatesTests {
    let page = URL(string: "https://github.com/ramdanegie/dylan/releases/tag/x")!

    @Test func semverOrdering() {
        #expect(SemVer("v0.1.2")! > SemVer("0.1.1")!)
        #expect(SemVer("0.10.0")! > SemVer("0.9.9")!)
        #expect(SemVer("1.2")! == SemVer("1.2.0")!)
        #expect(SemVer("1.2.0-beta.2")! < SemVer("1.2.0")!)
        #expect(SemVer("1.2.0-beta.10")! > SemVer("1.2.0-beta.2")!)
        #expect(SemVer("latest") == nil)
        #expect(SemVer("v1.1.1")!.description == "1.1.1")
    }

    @Test func picksTheNewestEligibleRelease() {
        let r = [
            ReleaseInfo(tag: "v0.1.0", prerelease: true, htmlURL: page),
            ReleaseInfo(tag: "v0.1.3", draft: true, htmlURL: page),
            ReleaseInfo(tag: "v0.1.2", prerelease: true, htmlURL: page,
                        assets: [.init(name: "Dylan-0.1.2.dmg", browserDownloadURL: URL(string: "https://x/Dylan-0.1.2.dmg")!)]),
            ReleaseInfo(tag: "nightly", htmlURL: page),
        ]
        #expect(Updates.newest(r, current: "0.1.1", includePrerelease: true)?.tag == "v0.1.2")
        #expect(Updates.newest(r, current: "0.1.1", includePrerelease: false) == nil)          // only pre-releases
        #expect(Updates.newest(r, current: "0.1.2", includePrerelease: true) == nil)           // up to date
        #expect(Updates.newest(r, current: "0.1.1", skipped: "0.1.2", includePrerelease: true) == nil)
        #expect(Updates.newest(r, current: "0.1.1", includePrerelease: true)?.downloadURL.lastPathComponent == "Dylan-0.1.2.dmg")
        #expect(r[0].downloadURL == page)                                                     // no DMG → release page
    }

    @Test func decodesGitHubReleases() throws {
        let json = #"[{"tag_name":"v0.1.1","name":"Dylan 0.1.1 (uji)","body":"notes","draft":false,"prerelease":true,"#
            + #""html_url":"https://github.com/ramdanegie/dylan/releases/tag/v0.1.1","#
            + #""assets":[{"name":"Dylan-0.1.1.dmg","browser_download_url":"https://github.com/x/Dylan-0.1.1.dmg","size":1}],"extra":1}]"#
        let r = try JSONDecoder().decode([ReleaseInfo].self, from: Data(json.utf8))
        #expect(r.first?.version == SemVer("0.1.1"))
        #expect(r.first?.assets.first?.name == "Dylan-0.1.1.dmg")
    }

    @Test func realGitHubPayload() throws {
        // Saved from api.github.com/repos/ramdanegie/dylan/releases on 4 Nov 2026 (v0.1.0, v0.1.1, both pre-releases).
        let data = try Data(contentsOf: #require(Bundle.module.url(forResource: "github-releases", withExtension: "json", subdirectory: "Fixtures")))
        let r = try JSONDecoder().decode([ReleaseInfo].self, from: data)
        #expect(r.map(\.tag) == ["v0.1.1", "v0.1.0"])
        let newest = Updates.newest(r, current: "0.1.0", includePrerelease: true)
        #expect(newest?.tag == "v0.1.1")
        #expect(newest?.downloadURL.lastPathComponent == "Dylan-0.1.1.dmg")
        #expect(newest?.body?.isEmpty == false)
        #expect(Updates.newest(r, current: "0.1.2", includePrerelease: true) == nil)
    }

    @Test func dailyCheck() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        #expect(Updates.isDue(lastCheck: nil, now: t))
        #expect(!Updates.isDue(lastCheck: t, now: t + 3600))
        #expect(Updates.isDue(lastCheck: t, now: t + 25 * 3600))
        #expect(Updates.isDue(lastCheck: t, now: t - 60))                                     // clock moved back
    }

    @Test func changelogSection() {
        let md = """
        # Changelog

        ## [Unreleased]
        - not yet

        ## [0.1.2] - 2026-11-04
        ### Added
        - Update check

        ## [0.1.1] - 2026-11-04
        - Smoother crosshair
        """
        #expect(Changelog.section(md, version: "0.1.2") == "### Added\n- Update check")
        #expect(Changelog.section(md, version: "v0.1.1") == "- Smoother crosshair")
        #expect(Changelog.section(md, version: "0.0.9") == nil)
    }

    @Test func whatsNewOnlyAfterAnUpdate() {
        #expect(Changelog.shouldShowWhatsNew(lastSeen: "0.1.1", current: "0.1.2"))
        #expect(!Changelog.shouldShowWhatsNew(lastSeen: nil, current: "0.1.2"))              // first install
        #expect(!Changelog.shouldShowWhatsNew(lastSeen: "0.1.2", current: "0.1.2"))
        #expect(!Changelog.shouldShowWhatsNew(lastSeen: "0.1.3", current: "0.1.2"))           // downgrade
    }
}
