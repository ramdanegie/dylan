import Testing
@testable import DylanCore

@Suite struct NotificationBannerTests {
    // Values as read from a real macOS 27.2 banner (spike T3.5).
    let raw = ["AXPress", "Name:Show Details\nTarget:0x0\nSelector:(null)", "Name:Show\nTarget:0x0\nSelector:(null)", "Name:Close\nTarget:0x0\nSelector:(null)"]

    @Test func parsesARealBanner() throws {
        let b = try #require(NotificationBanner(id: "F55E", description: "Script Editor, Dylan test, Rani, Slide sprint review sudah aku upload",
                                                title: "Dylan test", subtitle: "Rani", body: "Slide sprint review sudah aku upload", actionNames: raw))
        #expect(b.app == "Script Editor")
        #expect(b.actions == ["AXPress", "Show Details", "Show", "Close"])
        #expect(b.closeAction == "Close" && !b.canReply && !b.isCall)
        #expect(NotificationRules.detail(b) == "Dylan test · Rani · Slide sprint review sudah aku upload")
    }

    @Test func replyAndCalls() throws {
        let msg = try #require(NotificationBanner(id: "1", description: "WhatsApp, Rani Pratama, Tolong cek demo", title: "Rani Pratama", subtitle: nil,
                                                  body: "Tolong cek demo", actionNames: ["AXPress", "Name:Reply\nTarget:0x0", "Name:Close\nTarget:0x0"]))
        #expect(msg.app == "WhatsApp" && msg.canReply && msg.replyAction == "Reply")
        let call = try #require(NotificationBanner(id: "2", description: "FaceTime, Ibu, FaceTime Audio", title: "Ibu", subtitle: nil,
                                                   body: "FaceTime Audio", actionNames: ["Name:Decline", "Name:Accept"]))
        #expect(call.isCall && call.acceptAction == "Accept" && call.declineAction == "Decline")
        #expect(NotificationBanner(id: "3", description: "X", title: "", subtitle: nil, body: "", actionNames: []) == nil)
        let invite = try #require(NotificationBanner(id: "4", description: "Calendar, Sprint review, Today 14.00", title: "Sprint review", subtitle: nil,
                                                     body: "Today 14.00", actionNames: ["Name:Accept", "Name:Decline"]))
        #expect(!invite.isCall)   // not a phone call: allow-list applies, no P0
    }

    @Test func allowList() throws {
        let b = try #require(NotificationBanner(id: "1", description: "Slack, #eng, deploy done", title: "#eng", subtitle: nil, body: "deploy done", actionNames: []))
        #expect(NotificationRules.allowed(b, apps: ["slack", " Mail "]))
        #expect(!NotificationRules.allowed(b, apps: ["Mail"]))
        #expect(NotificationRules.allowed(b, apps: []))
        let call = try #require(NotificationBanner(id: "2", description: "FaceTime, Ibu, Audio", title: "Ibu", subtitle: nil, body: "Audio", actionNames: ["Accept", "Decline"]))
        #expect(NotificationRules.allowed(call, apps: ["Mail"]))
    }
}
