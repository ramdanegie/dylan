import Foundation
import Testing
@testable import DylanCore

@Suite struct StorageTests {
    let home = "/Users/gg"

    @Test func removableOnlyInsideHomeAndBelowTheRoots() {
        for ok in ["/Users/gg/Library/Caches/com.spotify.client", "/Users/gg/Library/Logs/DiagnosticReports",
                   "/Users/gg/.Trash/old.dmg", "/Users/gg/.npm/_cacache", "/Users/gg/Downloads/Xcode_16.xip",
                   "/Users/gg/Library/Developer/Xcode/DerivedData/App-abc", "/Users/gg/code/web/node_modules",
                   "/Users/gg/Library/Application Support/Dylan/Captures"] {
            #expect(StorageRules.isRemovable(ok, home: home), "\(ok)")
        }
        for no in ["/Users/gg", "/Users/gg/", "/Users/gg/Documents", "/Users/gg/Library", "/Users/gg/Library/Caches",
                   "/Users/gg/.Trash", "/Users/gg/.ssh", "/Users/gg/.zshrc", "/Users/ggg/Library/Caches/x", "/Users/other/Downloads/a",
                   "/Library/Caches/com.apple.x", "/Users/gg/Library/Caches/../Keychains/login.keychain-db",
                   "/Users/gg/Library/Mobile Documents/com~apple~CloudDocs/a.pdf", "/Users/gg/Library/CloudStorage/GoogleDrive/x",
                   "/Users/gg/Library/Keychains/login.keychain-db", "/Users/gg/Pictures/Photos Library.photoslibrary",
                   "/Users/gg/Pictures/Photos Library.photoslibrary/originals/a.heic", "/Users/gg/Music/Music/Music Library.musiclibrary",
                   "/Users/gg/Library/Containers/com.apple.mail/Data/x", "/Users/gg/Library/Messages/Attachments/x"] {
            #expect(!StorageRules.isRemovable(no, home: home), "\(no)")
        }
    }

    @Test func staleDownloads() {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        let old = now - 31 * 86_400, week = now - 8 * 86_400, fresh = now - 3600
        #expect(StorageRules.isStaleDownload(name: "movie.mov", size: 2 * StorageRules.gb, modified: old, now: now))
        #expect(!StorageRules.isStaleDownload(name: "movie.mov", size: 2 * StorageRules.gb, modified: week, now: now))   // big but recent
        #expect(!StorageRules.isStaleDownload(name: "notes.pdf", size: 5 * StorageRules.mb, modified: old, now: now))     // old but small
        #expect(StorageRules.isStaleDownload(name: "Zoom.PKG", size: 40 * StorageRules.mb, modified: week, now: now))     // installer after a week
        #expect(!StorageRules.isStaleDownload(name: "Zoom.pkg", size: 40 * StorageRules.mb, modified: fresh, now: now))
    }

    @Test func lowSpaceThresholds() {
        let gb = StorageRules.gb
        #expect(StorageRules.isLowSpace(free: 8 * gb, total: 500 * gb))       // under 10 GB
        #expect(StorageRules.isLowSpace(free: 20 * gb, total: 256 * gb))      // under 10 %
        #expect(!StorageRules.isLowSpace(free: 60 * gb, total: 500 * gb))
        #expect(!StorageRules.isLowSpace(free: 0, total: 0))
    }

    @Test func cacheFolderBundleIDs() {
        #expect(StorageRules.bundleID(cacheFolder: "com.spotify.client") == "com.spotify.client")
        #expect(StorageRules.bundleID(cacheFolder: "Homebrew") == nil)
        #expect(StorageRules.bundleID(cacheFolder: "Google") == "com.google.Chrome")   // Chrome's cache folder
        #expect(StorageRules.bundleID(cacheFolder: "com.apple.nsurlsessiond.noindex") == nil)
    }

    @Test func defaultsAndPlan() {
        let cache = StorageItem(category: .appCaches, title: "Spotify", path: "/Users/gg/Library/Caches/com.spotify.client", size: 900)
        let running = StorageItem(category: .appCaches, title: "Chrome", path: "/Users/gg/Library/Caches/com.google.Chrome", size: 500, running: true)
        let movie = StorageItem(category: .largeFiles, title: "a.mov", path: "/Users/gg/Movies/a.mov", size: 4000)
        #expect(cache.selectedByDefault && !running.selectedByDefault && !movie.selectedByDefault)
        let p = StorageRules.plan([cache, running, movie], selected: [cache.id, movie.id])
        #expect(p == StorageRules.Plan(count: 2, bytes: 4900, deleted: 1, trashed: 1))
    }

    @Test func userDataIsNeverDeletedOutright() {
        for c in StorageCategory.allCases where c.impact == .high { #expect(c.action == .trash, "\(c)") }
        for c in StorageCategory.allCases where c.impact == .low { #expect(c.action == .delete, "\(c)") }
    }
}
