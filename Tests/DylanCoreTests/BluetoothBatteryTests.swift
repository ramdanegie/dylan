import Foundation
import Testing
@testable import DylanCore

@Suite struct BluetoothBatteryTests {
    func fixture() throws -> Data {
        try Data(contentsOf: #require(Bundle.module.url(forResource: "bluetooth-connected", withExtension: "json", subdirectory: "Fixtures")))
    }

    @Test func parsesConnectedDevicesOnly() throws {
        let b = BluetoothBattery.parse(try fixture())
        #expect(b["51-04-B2-F0-0E-48"] == .init(left: 80, right: 75, case_: 40, main: nil))
        #expect(b["80-99-E7-13-DE-FA"] == .init(left: nil, right: nil, case_: nil, main: 60))
        #expect(b["D8-39-95-FD-07-08"] == nil)      // no battery reported
        #expect(b["E5-C2-C4-31-7F-C7"] == nil)      // not connected
        #expect(BluetoothBattery.parse(Data("{}".utf8)).isEmpty)
    }

    @Test func summaries() {
        #expect(BluetoothBattery.summary(.init(left: 80, right: 75, case_: 40, main: nil)) == "L 80% R 75% Case 40%")
        #expect(BluetoothBattery.summary(.init(left: 80, right: nil, case_: nil, main: nil), left: "Ki") == "Ki 80%")
        #expect(BluetoothBattery.summary(.init(left: nil, right: nil, case_: nil, main: 60)) == "60%")
        #expect(BluetoothBattery.lowest(.init(left: 80, right: 75, case_: 40, main: nil)) == 75)
        #expect(BluetoothBattery.normalize("e5:c2:c4:31:7f:c7") == "E5-C2-C4-31-7F-C7")
        #expect(BluetoothBattery.percent("120%") == nil)
    }
}
