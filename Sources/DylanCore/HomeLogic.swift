import Foundation

/// "Rapat tim besok 10.00" → event; "Beli kopi jam 3" → reminder (FR-85).
/// NSDataDetector handles English; Indonesian day words and "10.00" times are parsed here.
public enum QuickAdd {
    public struct Result: Equatable, Sendable {
        public enum Kind: Sendable, Equatable { case event, reminder }
        public var kind: Kind
        public var title: String
        public var date: Date?
        public var hasTime: Bool
    }

    static let meetingWords = ["rapat", "meeting", "standup", "call", "sync", "1:1", "review", "demo", "interview", "wawancara"]
    static let days: [(String, Int)] = [("minggu", 1), ("senin", 2), ("selasa", 3), ("rabu", 4), ("kamis", 5), ("jumat", 6), ("sabtu", 7)]

    public static func parse(_ input: String, now: Date, calendar: Calendar = .current) -> Result? {
        var text = " " + input.trimmingCharacters(in: .whitespacesAndNewlines) + " "
        guard text.count > 2 else { return nil }
        let lower = text.lowercased()
        var day: Date?
        var hour: Int?, minute = 0

        // Day words.
        let today = calendar.startOfDay(for: now)
        for (word, offset) in [("hari ini", 0), ("besok", 1), ("lusa", 2), ("today", 0), ("tomorrow", 1)] where lower.contains(" \(word) ") {
            day = calendar.date(byAdding: .day, value: offset, to: today)
            text = text.replacingOccurrences(of: " \(word) ", with: " ", options: .caseInsensitive)
        }
        if day == nil {
            for (word, weekday) in days where lower.contains(" \(word) ") {
                var ahead = (weekday - calendar.component(.weekday, from: now) + 7) % 7
                if ahead == 0 { ahead = 7 }
                day = calendar.date(byAdding: .day, value: ahead, to: today)
                text = text.replacingOccurrences(of: " \(word) ", with: " ", options: .caseInsensitive)
            }
        }
        // Times: "10.00", "10:30", "jam 3", "jam 15.30", "pukul 9".
        let timeRe = try! NSRegularExpression(pattern: #"(?i)\s(?:(?:jam|pukul|at)\s+)?(\d{1,2})(?:[.:](\d{2}))?(\s?(?:pagi|siang|sore|malam|am|pm))?(?=\s)"#)
        let ns = text as NSString
        for m in timeRe.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let whole = ns.substring(with: m.range).lowercased()
            let explicit = whole.contains("jam") || whole.contains("pukul") || whole.contains("at ") || m.range(at: 2).location != NSNotFound
            guard explicit, var h = Int(ns.substring(with: m.range(at: 1))), h <= 23 else { continue }
            let mm = m.range(at: 2).location != NSNotFound ? Int(ns.substring(with: m.range(at: 2))) ?? 0 : 0
            guard mm < 60 else { continue }
            let suffix = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces).lowercased() : ""
            if ["sore", "malam", "pm"].contains(suffix) && h < 12 { h += 12 }
            if ["siang"].contains(suffix) && h < 11 { h += 12 }
            if suffix.isEmpty && !whole.contains(":") && !whole.contains(".") && h < 7 { h += 12 }   // "jam 3" = 15:00
            hour = h; minute = mm
            text = ns.replacingCharacters(in: m.range, with: " ")
            break
        }
        // English fallback ("next friday at 4pm").
        if day == nil && hour == nil, let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
           let m = det.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)), let d = m.date {
            let title = (input as NSString).replacingCharacters(in: m.range, with: "").trimmingCharacters(in: .whitespaces)
            let isMeeting = meetingWords.contains { lower.contains($0) }
            return Result(kind: isMeeting ? .event : .reminder, title: title.isEmpty ? input : title, date: d, hasTime: true)
        }
        var date: Date?
        if let hour {
            let base = day ?? today
            date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)
            if day == nil, let d = date, d < now { date = calendar.date(byAdding: .day, value: 1, to: d) }
        } else if let day { date = day }
        let title = text.split(separator: " ").joined(separator: " ")
        guard !title.isEmpty else { return nil }
        let isMeeting = meetingWords.contains { lower.contains($0) }
        return Result(kind: isMeeting && hour != nil ? .event : .reminder, title: title, date: date, hasTime: hour != nil)
    }
}

/// Open-Meteo (FR-45): no API key; WMO weather codes → SF Symbol + description key.
public enum Weather {
    public struct Current: Equatable, Sendable {
        public var temperature: Double
        public var code: Int
        public var high: Double?
        public var low: Double?
        public var hourly: [(time: Date, temperature: Double, code: Int)]
        public static func == (a: Current, b: Current) -> Bool {
            a.temperature == b.temperature && a.code == b.code && a.high == b.high && a.low == b.low && a.hourly.count == b.hourly.count
        }
    }

    /// Coordinates are rounded to 2 decimals (about 1 km) before they leave the Mac (PRD §2.8).
    public static func forecastURL(latitude: Double, longitude: Double) -> URL? {
        func r(_ v: Double) -> String { String(format: "%.2f", v) }
        return URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(r(latitude))&longitude=\(r(longitude))"
                   + "&current=temperature_2m,weather_code&hourly=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min"
                   + "&forecast_days=2&timezone=auto")
    }

    public static func geocodeURL(city: String, language: String) -> URL? {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1"), URLQueryItem(name: "language", value: language)]
        return c.url
    }

    public static func parseGeocode(_ data: Data) -> (name: String, latitude: Double, longitude: Double)? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let r = (o["results"] as? [[String: Any]])?.first,
              let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double else { return nil }
        return (r["name"] as? String ?? "", lat, lon)
    }

    public static func parseForecast(_ data: Data, now: Date) -> Current? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = o["current"] as? [String: Any], let t = (cur["temperature_2m"] as? NSNumber)?.doubleValue,
              let code = (cur["weather_code"] as? NSNumber)?.intValue else { return nil }
        let daily = o["daily"] as? [String: Any]
        let high = ((daily?["temperature_2m_max"] as? [NSNumber])?.first)?.doubleValue
        let low = ((daily?["temperature_2m_min"] as? [NSNumber])?.first)?.doubleValue
        var hourly: [(Date, Double, Int)] = []
        if let h = o["hourly"] as? [String: Any], let times = h["time"] as? [String], let temps = h["temperature_2m"] as? [NSNumber],
           let codes = h["weather_code"] as? [NSNumber] {
            let offset = (o["utc_offset_seconds"] as? NSNumber)?.intValue ?? 0
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: offset)
            f.dateFormat = "yyyy-MM-dd'T'HH:mm"
            for (i, s) in times.enumerated() where i < temps.count && i < codes.count {
                if let d = f.date(from: s), d >= now.addingTimeInterval(-1800) { hourly.append((d, temps[i].doubleValue, codes[i].intValue)) }
            }
        }
        return Current(temperature: t, code: code, high: high, low: low, hourly: Array(hourly.prefix(12)))
    }

    /// WMO code → (SF Symbol, string key). https://open-meteo.com/en/docs (weather_code).
    public static func describe(_ code: Int) -> (symbol: String, key: String) {
        switch code {
        case 0: return ("sun.max.fill", "weather.clear")
        case 1, 2: return ("cloud.sun.fill", "weather.partly")
        case 3: return ("cloud.fill", "weather.cloudy")
        case 45, 48: return ("cloud.fog.fill", "weather.fog")
        case 51...57: return ("cloud.drizzle.fill", "weather.drizzle")
        case 61...67, 80...82: return ("cloud.rain.fill", "weather.rain")
        case 71...77, 85, 86: return ("cloud.snow.fill", "weather.snow")
        case 95...99: return ("cloud.bolt.rain.fill", "weather.storm")
        default: return ("cloud.fill", "weather.cloudy")
        }
    }

    /// First hour with rain in the forecast, for "Hujan 15.00" (design D33).
    public static func nextRain(_ c: Current) -> Date? {
        c.hourly.first { (51...67).contains($0.code) || (80...82).contains($0.code) || (95...99).contains($0.code) }?.time
    }
}
