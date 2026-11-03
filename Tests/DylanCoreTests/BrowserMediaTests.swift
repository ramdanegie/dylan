import Testing
@testable import DylanCore

@Suite struct BrowserMediaTests {
    @Test func picksTheMediaTab() {
        let tabs: [(title: String, url: String)] = [
            ("Inbox (3) - Gmail", "https://mail.google.com/mail/u/0/#inbox"),
            ("(2) Sore di Kemang - Arsa - YouTube", "https://www.youtube.com/watch?v=abc"),
        ]
        #expect(BrowserMedia.pick(tabs) == .init(title: "Sore di Kemang - Arsa", artist: "", site: "YouTube"))
        #expect(BrowserMedia.pick([("YouTube", "https://www.youtube.com/")]) == nil)    // home page, not a video
    }

    @Test func sites() {
        #expect(BrowserMedia.item(title: "Senja di Selatan - YouTube Music", url: "https://music.youtube.com/watch?v=x")?.site == "YouTube Music")
        #expect(BrowserMedia.item(title: "Stream Lo-fi Pagi by Kota | Listen online for free on SoundCloud", url: "https://soundcloud.com/kota/lofi")
                == .init(title: "Lo-fi Pagi", artist: "Kota", site: "SoundCloud"))
        #expect(BrowserMedia.item(title: "Fokus • Arsa", url: "https://open.spotify.com/track/1") == .init(title: "Fokus", artist: "Arsa", site: "Spotify Web"))
        #expect(BrowserMedia.item(title: "Spotify – Web Player", url: "https://open.spotify.com/") == nil)
        #expect(BrowserMedia.item(title: "dev stream - Twitch", url: "https://www.twitch.tv/someone")?.title == "dev stream")
        #expect(BrowserMedia.item(title: "x", url: "not a url") == nil)
    }

    @Test func scriptsAndVLC() {
        #expect(BrowserMedia.tabsScript(bundleID: "com.apple.Safari").contains("name of t"))
        #expect(BrowserMedia.tabsScript(bundleID: "com.google.Chrome").contains("title of t"))
        #expect(BrowserMedia.parseTabs("A\thttps://a\nB\thttps://b\n").map(\.url) == ["https://a", "https://b"])
        let v = BrowserMedia.parseVLC("true\tFilm Keluarga.mkv\t5400\t61")
        #expect(v?.playing == true && v?.title == "Film Keluarga" && v?.duration == 5400 && v?.position == 61)
        #expect(BrowserMedia.parseVLC("") == nil)
    }

    @Test func navigationPagesAreNotMedia() {
        #expect(BrowserMedia.item(title: "YouTube Music", url: "https://music.youtube.com/") == nil)
        #expect(BrowserMedia.item(title: "Apple Music - Web Player", url: "https://music.apple.com/us/browse") == nil)
        #expect(BrowserMedia.item(title: "Stream", url: "https://soundcloud.com/feed") == nil)
        #expect(BrowserMedia.item(title: "Browse - Twitch", url: "https://www.twitch.tv/directory") == nil)
        #expect(BrowserMedia.item(title: "Lagu - Apple Music", url: "https://music.apple.com/id/album/x/123")?.title == "Lagu")
        #expect(BrowserMedia.parseVLC("false\tLive at 10.30\t0\t0")?.title == "Live at 10.30")
        #expect(BrowserMedia.parseVLC("true\tKonser.MP4\t60\t1")?.title == "Konser")
    }
}
