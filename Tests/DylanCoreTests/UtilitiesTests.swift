import Foundation
import Testing
@testable import DylanCore

private let t0 = Date(timeIntervalSince1970: 4_000_000)

@Suite struct KeepAwakeTests {
    @Test func timedAndIndefinite() {
        let k = KeepAwake.start(duration: 900, now: t0)
        #expect(k.remaining(now: t0.addingTimeInterval(300)) == 600)
        #expect(!k.shouldStop(now: t0.addingTimeInterval(899), battery: nil, stopBelow: 20))
        #expect(k.shouldStop(now: t0.addingTimeInterval(900), battery: nil, stopBelow: 20))
        let forever = KeepAwake.start(duration: nil, now: t0)
        #expect(forever.remaining(now: t0) == nil)
        #expect(!forever.shouldStop(now: t0.addingTimeInterval(1e6), battery: nil, stopBelow: 20))
    }

    @Test func lowBatteryStopsOnlyOnBattery() {
        let k = KeepAwake.start(duration: nil, now: t0)
        #expect(k.shouldStop(now: t0, battery: BatterySnapshot(percent: 19, isCharging: false, onAC: false), stopBelow: 20))
        #expect(!k.shouldStop(now: t0, battery: BatterySnapshot(percent: 19, isCharging: true, onAC: true), stopBelow: 20))
        #expect(!k.shouldStop(now: t0, battery: BatterySnapshot(percent: 5, isCharging: false, onAC: false), stopBelow: 0))
    }
}

@Suite struct ColorTests {
    @Test func designExample() throws {
        // Design D34: #FF6B35 → RGB 255 107 53 → HSL 16° 100% 60%.
        let c = try #require(PickedColor(hex: "#FF6B35"))
        #expect(c.hex == "#FF6B35")
        #expect(c.rgb == "rgb(255 107 53)")
        #expect(c.hsl == "16° 100% 60%")
        #expect(c.swiftUI == "Color(red: 1, green: 0.42, blue: 0.21)")
    }

    @Test func greysAndBadInput() {
        #expect(PickedColor(r: 0.5, g: 0.5, b: 0.5).hsl == "0° 0% 50%")
        #expect(PickedColor(r: 2, g: -1, b: 0).hex == "#FF0000")
        #expect(PickedColor(hex: "#12345") == nil)
        #expect(PickedColor(hex: "zzzzzz") == nil)
    }
}

@Suite struct TouchIDSudoTests {
    @Test func detectsEnabledLine() {
        #expect(!TouchIDSudo.isEnabled(sudoLocal: nil))
        #expect(!TouchIDSudo.isEnabled(sudoLocal: "# sudo_local: local config\n#auth       sufficient     pam_tid.so\n"))
        #expect(TouchIDSudo.isEnabled(sudoLocal: "# sudo_local\nauth       sufficient     pam_tid.so\n"))
    }

    @Test func tmuxNeedsReattach() {
        let on = "auth sufficient pam_tid.so\n"
        #expect(TouchIDSudo.needsReattach(sudoLocal: on, multiplexerRunning: true))
        #expect(!TouchIDSudo.needsReattach(sudoLocal: "auth optional /opt/homebrew/lib/pam/pam_reattach.so\n" + on, multiplexerRunning: true))
        #expect(!TouchIDSudo.needsReattach(sudoLocal: on, multiplexerRunning: false))
    }
}
