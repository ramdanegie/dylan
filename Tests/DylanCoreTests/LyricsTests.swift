import Foundation
import Testing
@testable import DylanCore

@Suite struct LyricsTests {
    let lrc = """
    [ar:Arsa]
    [ti:Sore di Kemang]
    [00:12.50]Langit jingga di atas kota
    [00:17.00][01:05.25]Kita pulang pelan-pelan
    [00:21.8]Lampu jalan mulai menyala
    """

    @Test func parsesTagsAndRepeats() {
        let l = Lyrics.parseLRC(lrc)
        #expect(l.lines.map(\.time) == [12.5, 17, 21.8, 65.25])
        #expect(l.lines[3].text == "Kita pulang pelan-pelan")
        #expect(l.synced)
    }

    @Test func currentLine() {
        let l = Lyrics.parseLRC(lrc)
        #expect(l.index(at: 5) == nil)
        #expect(l.index(at: 12.5) == 0)
        #expect(l.index(at: 20) == 1)
        #expect(l.index(at: 30) == 2)
        #expect(l.index(at: 300) == 3)
        #expect(Lyrics.plain("a\nb").index(at: 10) == nil)
    }

    @Test func offsetShiftsEarlier() {
        let l = Lyrics.parseLRC("[offset:+500]\n[00:10.00]x")
        #expect(l.lines[0].time == 9.5)
    }

    @Test func lrclibResponses() throws {
        let synced = try #require(Lyrics.fromLRCLIB(Data(#"{"syncedLyrics":"[00:01.00]a\n[00:02.00]b","plainLyrics":"a\nb"}"#.utf8)))
        #expect(synced.synced && synced.lines.count == 2)
        let plain = try #require(Lyrics.fromLRCLIB(Data(#"{"syncedLyrics":null,"plainLyrics":"a\nb"}"#.utf8)))
        #expect(!plain.synced)
        #expect(Lyrics.fromLRCLIB(Data(#"{"instrumental":true}"#.utf8)) == nil)
        #expect(Lyrics.fromLRCLIB(Data("not json".utf8)) == nil)
        let url = try #require(Lyrics.lrclibURL(title: "Sore di Kemang", artist: "Arsa", album: "Senja", duration: 237.6))
        #expect(url.absoluteString.contains("duration=238") && url.absoluteString.contains("track_name=Sore%20di%20Kemang"))
    }

    @Test(arguments: [
        ("https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc", "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"),
        ("https://open.spotify.com/intl-id/album/4aawyAB9vmqN3uQ7FjRGTy", "spotify:album:4aawyAB9vmqN3uQ7FjRGTy"),
        ("spotify:playlist:37i9dQZF1DXcBWIGoYBM5M", "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"),
    ])
    func spotifyLinks(_ input: String, _ uri: String) { #expect(SpotifyLink.uri(from: input) == uri) }

    @Test(arguments: ["https://example.com/playlist/37i9dQZF1DXcBWIGoYBM5M", "spotify:playlist:x\" & do shell script \"rm", "hello"])
    func rejectsOtherInput(_ s: String) { #expect(SpotifyLink.uri(from: s) == nil) }
}
