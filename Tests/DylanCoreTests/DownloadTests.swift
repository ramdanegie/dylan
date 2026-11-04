import Foundation
import Testing
@testable import DylanCore

@Suite struct DownloadTests {
    @Test func classifies() {
        #expect(DownloadWatcher.classify("/u/Downloads/Figma.dmg.crdownload") == .init(path: "/u/Downloads/Figma.dmg.crdownload", browser: .chrome, finalName: "Figma.dmg"))
        #expect(DownloadWatcher.classify("/u/Downloads/video.mp4.part")?.browser == .firefox)
        #expect(DownloadWatcher.classify("/u/Downloads/Report.pdf.download")?.finalName == "Report.pdf")
        #expect(DownloadWatcher.classify("/u/Downloads/Unconfirmed 812.crdownload")?.finalName == "Download")
        #expect(DownloadWatcher.classify("/u/Downloads/notes.txt") == nil)
        #expect(DownloadWatcher.classify("/u/Downloads/.crdownload") == nil)
    }

    @Test func safariProgress() throws {
        let plist = try PropertyListSerialization.data(fromPropertyList: ["DownloadEntryProgressBytesSoFar": 620, "DownloadEntryProgressTotalToLoad": 1000],
                                                       format: .xml, options: 0)
        #expect(DownloadWatcher.safariProgress(infoPlist: plist) == 0.62)
        #expect(DownloadWatcher.safariProgress(infoPlist: Data("x".utf8)) == nil)
    }

    @Test func finished() throws {
        let p = try #require(DownloadWatcher.classify("/d/Figma.dmg.crdownload"))
        #expect(DownloadWatcher.finishedPath(p, exists: { $0 == "/d/Figma.dmg.crdownload" }) == nil)   // still downloading
        #expect(DownloadWatcher.finishedPath(p, exists: { $0 == "/d/Figma.dmg" }) == "/d/Figma.dmg")
        #expect(DownloadWatcher.finishedPath(p, exists: { _ in false }) == nil)                          // cancelled
    }
}
