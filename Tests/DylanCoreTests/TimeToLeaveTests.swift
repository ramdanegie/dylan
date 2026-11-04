import Foundation
import Testing
@testable import DylanCore

@Suite struct TimeToLeaveTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func physicalPlaces() {
        #expect(TimeToLeave.physicalPlace("Kantor Pusat, Jl. Sudirman 1") == "Kantor Pusat, Jl. Sudirman 1")
        #expect(TimeToLeave.physicalPlace("https://zoom.us/j/123") == nil)
        #expect(TimeToLeave.physicalPlace("meet.google.com/abc-defg-hij") == nil)
        #expect(TimeToLeave.physicalPlace("Online") == nil)
        #expect(TimeToLeave.physicalPlace("  ") == nil)
        #expect(TimeToLeave.physicalPlace(nil) == nil)
    }

    @Test func candidatesAndTiming() {
        func ev(_ id: String, in minutes: Double, place: String? = "Kantor", allDay: Bool = false) -> MeetingSchedule.Event {
            .init(id: id, title: id, start: now.addingTimeInterval(minutes * 60), end: now.addingTimeInterval(minutes * 60 + 3600),
                  link: nil, isAllDay: allDay, place: place)
        }
        let list = [ev("later", in: 200), ev("soon", in: 50), ev("past", in: -10), ev("online", in: 30, place: nil), ev("allday", in: 20, allDay: true)]
        #expect(TimeToLeave.candidates(list, now: now).map(\.id) == ["soon"])
        let start = now.addingTimeInterval(50 * 60)
        #expect(TimeToLeave.leaveAt(start: start, travel: 30 * 60) == now.addingTimeInterval(15 * 60))
        #expect(!TimeToLeave.shouldAlert(now: now, start: start, travel: 30 * 60, alreadyAlerted: false))
        #expect(TimeToLeave.shouldAlert(now: now.addingTimeInterval(15 * 60), start: start, travel: 30 * 60, alreadyAlerted: false))
        #expect(!TimeToLeave.shouldAlert(now: now.addingTimeInterval(15 * 60), start: start, travel: 30 * 60, alreadyAlerted: true))
        #expect(!TimeToLeave.shouldAlert(now: start, start: start, travel: 30 * 60, alreadyAlerted: false))
    }

    @Test func plausibleRoutesOnly() {
        #expect(TimeToLeave.isPlausible(travel: 25 * 60, distanceMeters: 12_000))
        #expect(!TimeToLeave.isPlausible(travel: 9 * 3600, distanceMeters: 600_000))   // "Lt. 3" matched another city
        #expect(!TimeToLeave.isPlausible(travel: 20, distanceMeters: 50))              // already there
    }
}
