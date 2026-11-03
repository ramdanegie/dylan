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
