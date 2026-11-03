import Testing
@testable import DylanCore

@Suite struct MeetingControlsTests {
    @Test func detectsTheCallApp() {
        #expect(MeetingControls.app(bundleID: "us.zoom.xos", windowTitle: nil) == .zoom)
        #expect(MeetingControls.app(bundleID: "com.microsoft.teams2", windowTitle: nil) == .teams)
        #expect(MeetingControls.app(bundleID: "com.google.Chrome", windowTitle: "Meet - abc-defg-hij") == .meet)
        #expect(MeetingControls.app(bundleID: "com.apple.Safari", windowTitle: "Meet – Standup") == .meet)
        #expect(MeetingControls.app(bundleID: "com.google.Chrome", windowTitle: "YouTube") == nil)
        #expect(MeetingControls.app(bundleID: "com.google.Chrome", windowTitle: nil) == nil)
        #expect(MeetingControls.app(bundleID: "com.hnc.Discord", windowTitle: nil) == nil)
        #expect(MeetingControls.app(bundleID: nil, windowTitle: "Meet - x") == nil)
    }

    @Test func shortcuts() {
        #expect(MeetingControls.shortcut(.zoom, .mic) == .init(key: "A", shift: true))
        #expect(MeetingControls.shortcut(.zoom, .mic)?.axModifiers == 1)
        #expect(MeetingControls.shortcut(.meet, .camera)?.axModifiers == 0)
        #expect(MeetingControls.shortcut(.meet, .share) == nil)
        for app in MeetingControls.App.allCases { #expect(MeetingControls.shortcut(app, .mic) != nil) }
    }
}

@Suite struct ScreenShareTests {
    @Test func sharingWindows() {
        #expect(MeetingControls.isSharing(.zoom, windowTitles: ["Zoom Meeting", "zoom share toolbar window"]))
        #expect(MeetingControls.isSharing(.meet, windowTitles: ["meet.google.com is sharing your screen."]))
        #expect(MeetingControls.isSharing(.teams, windowTitles: ["Sharing control bar | Microsoft Teams"]))
        #expect(!MeetingControls.isSharing(.zoom, windowTitles: ["Zoom Meeting", "Participants"]))
        #expect(!MeetingControls.isSharing(.meet, windowTitles: ["Meet - abc-defg-hij - Google Chrome"]))
        #expect(!MeetingControls.isSharing(.teams, windowTitles: []))
    }
}
