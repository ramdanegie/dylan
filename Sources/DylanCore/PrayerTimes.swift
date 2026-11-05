import Foundation

/// Prayer times (FR-105, design D51) by the Kemenag RI method, computed on the Mac so they work offline:
/// Subuh at a sun depression of 20°, Isya at 18°, Asar when a shadow equals its object plus the noon shadow
/// (Syafi'i), Zuhur at transit, Magrib at sunset; then an ihtiyat (safety margin, default +2 min) and rounding
/// up to the minute. Sun position from the PrayTimes.org formulas.
public enum PrayerTimes {
    public enum Prayer: String, CaseIterable, Sendable, Codable {
        case fajr, sunrise, dhuhr, asr, maghrib, isha
        /// Sunrise is a time, not a prayer: no countdown, no adhan.
        public var isPrayer: Bool { self != .sunrise }
    }

    public struct Day: Equatable, Sendable {
        public var times: [Prayer: Date]
        public func time(_ p: Prayer) -> Date { times[p]! }
    }

    public static let fajrAngle = 20.0
    public static let ishaAngle = 18.0

    /// Times for the calendar day containing `date` in `timeZone`. `ihtiyat` in minutes is added to every prayer
    /// and taken off sunrise.
    public static func day(for date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current,
                           ihtiyat: Int = 2) -> Day {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        let midnight = cal.date(from: c)!
        let tz = Double(timeZone.secondsFromGMT(for: midnight.addingTimeInterval(12 * 3600))) / 3600
        let jDate = julian(c.year!, c.month!, c.day!) - longitude / (15 * 24)

        func sun(_ jd: Double) -> (decl: Double, eqt: Double) {
            let d = jd - 2451545.0
            let g = fix(357.529 + 0.98560028 * d, 360)
            let q = fix(280.459 + 0.98564736 * d, 360)
            let l = fix(q + 1.915 * sin(rad(g)) + 0.020 * sin(rad(2 * g)), 360)
            let e = 23.439 - 0.00000036 * d
            let ra = fix(deg(atan2(cos(rad(e)) * sin(rad(l)), cos(rad(l)))) / 15, 24)
            return (deg(asin(sin(rad(e)) * sin(rad(l)))), q / 15 - ra)
        }
        func midDay(_ t: Double) -> Double { fix(12 - sun(jDate + t).eqt, 24) }
        func angleTime(_ angle: Double, _ t: Double, ccw: Bool) -> Double {
            let decl = sun(jDate + t).decl
            let x = (-sin(rad(angle)) - sin(rad(decl)) * sin(rad(latitude))) / (cos(rad(decl)) * cos(rad(latitude)))
            let h = deg(acos(min(1, max(-1, x)))) / 15
            return midDay(t) + (ccw ? -h : h)
        }
        func asr(_ t: Double) -> Double {
            let decl = sun(jDate + t).decl
            let angle = -deg(atan(1 / (1 + tan(rad(abs(latitude - decl))))))
            return angleTime(angle, t, ccw: false)
        }

        // One refinement pass from the usual first guesses, as PrayTimes does.
        let raw: [Prayer: Double] = [
            .fajr: angleTime(fajrAngle, 5 / 24, ccw: true),
            .sunrise: angleTime(0.833, 6 / 24, ccw: true),
            .dhuhr: midDay(12 / 24),
            .asr: asr(13 / 24),
            .maghrib: angleTime(0.833, 18 / 24, ccw: false),
            .isha: angleTime(ishaAngle, 18 / 24, ccw: false),
        ]
        var out: [Prayer: Date] = [:]
        for (p, h) in raw {
            let local = h + tz - longitude / 15
            var seconds = local * 3600 + Double(p == .sunrise ? -ihtiyat : ihtiyat) * 60
            // Kemenag rounds prayers up and sunrise down, so the schedule never says "too early".
            seconds = p == .sunrise ? floor(seconds / 60) * 60 : ceil(seconds / 60) * 60
            out[p] = midnight.addingTimeInterval(seconds)
        }
        return Day(times: out)
    }

    /// The next prayer (not sunrise) after `now`, looking into tomorrow after Isya.
    public static func next(after now: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current,
                            ihtiyat: Int = 2) -> (prayer: Prayer, at: Date) {
        for offset in 0...1 {
            let d = day(for: now.addingTimeInterval(Double(offset) * 86400), latitude: latitude, longitude: longitude,
                        timeZone: timeZone, ihtiyat: ihtiyat)
            if let p = Prayer.allCases.first(where: { $0.isPrayer && d.time($0) > now }) { return (p, d.time(p)) }
        }
        let d = day(for: now.addingTimeInterval(86400), latitude: latitude, longitude: longitude, timeZone: timeZone, ihtiyat: ihtiyat)
        return (.fajr, d.time(.fajr))
    }

    /// "Zuhur" is "Jumat" on Fridays (D51).
    public static func isJumuah(_ p: Prayer, on date: Date, timeZone: TimeZone = .current) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return p == .dhuhr && cal.component(.weekday, from: date) == 6
    }

    /// "24 Jumadilawal 1448 H" style (Umm al-Qura; may differ a day from the Kemenag isbat).
    public static func hijri(_ date: Date, locale: Locale) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .islamicUmmAlQura)
        f.locale = locale
        f.dateFormat = "d MMMM y"
        return f.string(from: date) + " H"
    }

    static func julian(_ y: Int, _ m: Int, _ d: Int) -> Double {
        var y = Double(y), m = Double(m)
        if m <= 2 { y -= 1; m += 12 }
        let a = floor(y / 100), b = 2 - a + floor(a / 4)
        return floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + Double(d) + b - 1524.5
    }

    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }
    private static func fix(_ a: Double, _ b: Double) -> Double { let r = a - b * floor(a / b); return r < 0 ? r + b : r }
}
