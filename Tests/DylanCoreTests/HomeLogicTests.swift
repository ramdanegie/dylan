import Foundation
import Testing
@testable import DylanCore

@Suite struct QuickAddTests {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Jakarta")!; return c }()
    // Tuesday 3 Nov 2026, 09:41 WIB
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9, minute: 41))! }

    func comps(_ d: Date?) -> [Int] {
        guard let d else { return [] }
        let c = cal.dateComponents([.day, .hour, .minute], from: d)
        return [c.day!, c.hour!, c.minute!]
    }

    @Test func designExample() throws {
        let r = try #require(QuickAdd.parse("Rapat tim besok 10.00", now: now, calendar: cal))
        #expect(r.kind == .event && r.title == "Rapat tim" && r.hasTime)
        #expect(comps(r.date) == [4, 10, 0])
    }

    @Test func remindersAndTimes() throws {
        let a = try #require(QuickAdd.parse("Beli kopi jam 3", now: now, calendar: cal))
        #expect(a.kind == .reminder && a.title == "Beli kopi" && comps(a.date) == [3, 15, 0])
        let b = try #require(QuickAdd.parse("Telepon ibu jam 8 malam", now: now, calendar: cal))
        #expect(comps(b.date) == [3, 20, 0])
        let c = try #require(QuickAdd.parse("Kirim slide 08.30", now: now, calendar: cal))
        #expect(comps(c.date) == [4, 8, 30])                // already past today → tomorrow
        let d = try #require(QuickAdd.parse("Bayar listrik jumat", now: now, calendar: cal))
        #expect(d.kind == .reminder && !d.hasTime && comps(d.date) == [6, 0, 0])
        let e = try #require(QuickAdd.parse("Bayar listrik", now: now, calendar: cal))
        #expect(e.date == nil && e.title == "Bayar listrik")
    }

    @Test func numbersThatAreNotTimes() throws {
        let r = try #require(QuickAdd.parse("Beli 3 kopi", now: now, calendar: cal))
        #expect(r.title == "Beli 3 kopi" && r.date == nil)
        #expect(QuickAdd.parse("   ", now: now, calendar: cal) == nil)
    }
}

@Suite struct WeatherTests {
    let sample = #"""
    {"utc_offset_seconds":25200,"current":{"temperature_2m":31.2,"weather_code":2},
     "hourly":{"time":["2026-11-03T09:00","2026-11-03T10:00","2026-11-03T15:00"],"temperature_2m":[30,31,28],"weather_code":[2,3,63]},
     "daily":{"temperature_2m_max":[32.4],"temperature_2m_min":[25.1]}}
    """#

    @Test func parsesForecast() throws {
        let now = ISO8601DateFormatter().date(from: "2026-11-03T02:30:00Z")!   // 09:30 WIB
        let c = try #require(Weather.parseForecast(Data(sample.utf8), now: now))
        #expect(c.temperature == 31.2 && c.code == 2 && c.high == 32.4 && c.low == 25.1)
        #expect(c.hourly.count == 3)
        let rain = try #require(Weather.nextRain(c))
        #expect(ISO8601DateFormatter().string(from: rain) == "2026-11-03T08:00:00Z")   // 15:00 WIB
        #expect(Weather.describe(2).symbol == "cloud.sun.fill")
        #expect(Weather.describe(63).key == "weather.rain")
    }

    @Test func roundsCoordinates() throws {
        let u = try #require(Weather.forecastURL(latitude: -6.208763, longitude: 106.845599))
        #expect(u.absoluteString.contains("latitude=-6.21&longitude=106.85"))
        let g = try #require(Weather.parseGeocode(Data(#"{"results":[{"name":"Jakarta","latitude":-6.21,"longitude":106.85}]}"#.utf8)))
        #expect(g.name == "Jakarta")
        #expect(Weather.parseGeocode(Data("{}".utf8)) == nil)
    }
}
