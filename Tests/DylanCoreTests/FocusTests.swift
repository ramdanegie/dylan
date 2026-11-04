import Foundation
import Testing
@testable import DylanCore

@Suite struct FocusTests {
    func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }

    @Test func newestAssertionWins() throws {
        let m = FocusMode.active(assertions: try fixture("focus-assertions"), modes: try fixture("focus-modes"))
        #expect(m == .init(id: "com.apple.focus.work", name: "Kerja", symbol: "briefcase.fill"))
    }

    @Test func noneOrUnknown() throws {
        let off = Data(#"{"data":[{"storeAssertionRecords":[],"storeInvalidationRecords":[{}]}]}"#.utf8)
        #expect(FocusMode.active(assertions: off, modes: nil) == nil)
        #expect(FocusMode.active(assertions: Data("not json".utf8), modes: nil) == nil)
        // Without ModeConfigurations the id is still known.
        #expect(FocusMode.active(assertions: try fixture("focus-assertions"), modes: nil)?.name == nil)
    }
}
