import AppKit
import DylanCore
import EventKit

/// Reminders due today and overdue (FR-75), plus quick add (FR-85).
@Observable
final class RemindersProvider {
    static let shared = RemindersProvider()

    struct Item: Identifiable, Equatable, Sendable {
        var id: String
        var title: String
        var due: Date?
        var hasTime: Bool
        var overdue: Bool
    }

    var items: [Item] = []
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var dueTimers: [Timer] = []

    var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .reminder) }

    func start(requestAccess: Bool) {
        if status == .fullAccess { begin(); return }
        guard requestAccess, status == .notDetermined else { return }
        store.requestFullAccessToReminders { @Sendable granted, _ in
            Task { @MainActor in if granted { RemindersProvider.shared.begin() } }
        }
    }

    private func begin() {
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
                MainActor.assumeIsolated { RemindersProvider.shared.reload() }
            }
        }
        reload()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        dueTimers.forEach { $0.invalidate() }; dueTimers = []
        items = []
    }

    func reload() {
        guard status == .fullAccess, AppModel.shared.features.isEnabled(.reminders) else { return }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        // @Sendable: EventKit calls this on a background queue; a main-actor closure traps there.
        store.fetchReminders(matching: predicate) { @Sendable reminders in
            let now = Date()
            let mapped: [Item] = (reminders ?? []).compactMap { r in
                guard let dc = r.dueDateComponents, let due = Calendar.current.date(from: dc) else { return nil }
                return Item(id: r.calendarItemIdentifier, title: r.title ?? "", due: due, hasTime: dc.hour != nil,
                            overdue: dc.hour != nil ? due < now : Calendar.current.startOfDay(for: due) < Calendar.current.startOfDay(for: now))
            }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            Task { @MainActor in RemindersProvider.shared.loaded(mapped) }
        }
    }

    private func loaded(_ list: [Item]) {
        items = list
        // A P1 at the due time (FR-75).
        dueTimers.forEach { $0.invalidate() }
        dueTimers = list.compactMap { item in
            guard item.hasTime, let due = item.due, due > Date() else { return nil }
            let t = Timer(fire: due, interval: 0, repeats: false) { _ in
                MainActor.assumeIsolated {
                    let m = AppModel.shared
                    m.center.post(Activity(id: "reminder-\(item.id)", kind: .notify, priority: .p1, state: .info, symbol: "checklist",
                                           label: L("reminders.short"), detail: item.title, genericDetail: L("reminders.generic"),
                                           startedAt: Date()), now: Date())
                    m.scheduleTick()
                }
            }
            RunLoop.main.add(t, forMode: .common)
            return t
        }
    }

    func complete(_ item: Item) {
        guard let r = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        r.isCompleted = true
        try? store.save(r, commit: true)
        items.removeAll { $0.id == item.id }
    }

    /// Saves a quick-add result; returns a short confirmation or an error message.
    func save(_ r: QuickAdd.Result) -> String {
        do {
            switch r.kind {
            case .event:
                guard EKEventStore.authorizationStatus(for: .event) == .fullAccess, let start = r.date else { return L("quickAdd.needCalendar") }
                let e = EKEvent(eventStore: store)
                e.title = r.title
                e.startDate = start
                e.endDate = start.addingTimeInterval(30 * 60)
                e.calendar = store.defaultCalendarForNewEvents
                try store.save(e, span: .thisEvent)
            case .reminder:
                guard status == .fullAccess else { return L("quickAdd.needReminders") }
                let rem = EKReminder(eventStore: store)
                rem.title = r.title
                rem.calendar = store.defaultCalendarForNewReminders()
                if let d = r.date {
                    let units: Set<Calendar.Component> = r.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
                    rem.dueDateComponents = Calendar.current.dateComponents(units, from: d)
                    if r.hasTime { rem.addAlarm(EKAlarm(absoluteDate: d)) }
                }
                try store.save(rem, commit: true)
            }
            return r.kind == .event ? L("quickAdd.eventSaved") : L("quickAdd.reminderSaved")
        } catch {
            return error.localizedDescription
        }
    }
}

/// Weather from Open-Meteo every 30 minutes while the screen is on (FR-45). Opt-in (network).
@Observable
final class WeatherProvider {
    static let shared = WeatherProvider()

    var current: Weather.Current?
    var place: String?
    @ObservationIgnored private var coords: (Double, Double)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastFetch: Date?

    func start() {
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: 30 * 60, repeats: true) { _ in MainActor.assumeIsolated { WeatherProvider.shared.refresh() } }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil; current = nil }

    func cityChanged() { coords = nil; place = nil; refresh(force: true) }

    func refresh(force: Bool = false) {
        let city = AppModel.shared.weatherCity.trimmingCharacters(in: .whitespaces)
        guard !city.isEmpty, AppModel.shared.features.isEnabled(.weather) else { current = nil; return }
        if !force, let l = lastFetch, Date().timeIntervalSince(l) < 10 * 60 { return }
        lastFetch = Date()
        if let (lat, lon) = coords { fetch(lat, lon); return }
        guard let url = Weather.geocodeURL(city: city, language: L10n.language) else { return }
        URLSession.shared.dataTask(with: url) { @Sendable data, _, _ in
            guard let data, let g = Weather.parseGeocode(data) else { return }
            Task { @MainActor in
                let w = WeatherProvider.shared
                w.coords = (g.latitude, g.longitude)
                w.place = g.name
                w.fetch(g.latitude, g.longitude)
            }
        }.resume()
    }

    private func fetch(_ lat: Double, _ lon: Double) {
        guard let url = Weather.forecastURL(latitude: lat, longitude: lon) else { return }
        URLSession.shared.dataTask(with: url) { @Sendable data, _, _ in
            guard let data, let c = Weather.parseForecast(data, now: Date()) else { return }
            Task { @MainActor in WeatherProvider.shared.current = c }
        }.resume()
    }
}
