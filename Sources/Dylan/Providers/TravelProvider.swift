import AppKit
import CoreLocation
import DylanCore
import MapKit

/// "Time to leave" (FR-81): a P1 when it is time to go to an event at a physical place. Opt-in: needs
/// Location Services, and travel times come from Apple Maps. One location fix and one ETA per event,
/// refreshed every 10 minutes while such an event is within 3 hours.
final class TravelProvider: NSObject {
    static let shared = TravelProvider()
    private let manager = CLLocationManager()
    private var timer: Timer?
    private var travel: [String: TimeInterval] = [:]
    private var places: [String: CLLocationCoordinate2D] = [:]
    private var alerted: Set<String> = []
    private var alarms: [String: Timer] = [:]
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        let t = Timer(timeInterval: 10 * 60, repeats: true) { _ in MainActor.assumeIsolated { TravelProvider.shared.refresh() } }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    func stop() {
        running = false
        timer?.invalidate(); timer = nil
        alarms.values.forEach { $0.invalidate() }; alarms = [:]
        travel = [:]
        for id in AppModel.shared.center.activities.keys where id.hasPrefix("leave-") { AppModel.shared.removeIfPresent(id, now: Date()) }
    }

    /// Called every 10 minutes and when the calendar reloads.
    func refresh() {
        guard running, AppModel.shared.features.isEnabled(.timeToLeave),
              !TimeToLeave.candidates(AppModel.shared.meetings, now: Date()).isEmpty else { return }
        let s = manager.authorizationStatus
        guard s == .authorizedAlways || s == .authorized else { return }
        manager.requestLocation()
    }

    /// One timer per event at its leave time (re-armed when a new ETA arrives).
    private func arm(_ id: String) {
        alarms[id]?.invalidate()
        guard let e = AppModel.shared.meetings.first(where: { $0.id == id }), let t = travel[id] else { return }
        let at = TimeToLeave.leaveAt(start: e.start, travel: t)
        let timer = Timer(fire: max(at, Date()), interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { TravelProvider.shared.fire(id) }
        }
        RunLoop.main.add(timer, forMode: .common)
        alarms[id] = timer
    }

    private func fire(_ id: String) {
        let now = Date()
        alarms[id] = nil
        guard running, let e = AppModel.shared.meetings.first(where: { $0.id == id }), let t = travel[id],
              TimeToLeave.shouldAlert(now: now, start: e.start, travel: t, alreadyAlerted: alerted.contains(id)) else { return }
        alerted.insert(e.id)
        let minutes = Int((t / 60).rounded(.up))
        AppModel.shared.center.post(Activity(
            id: "leave-\(e.id)", kind: .meeting, priority: .p1, state: .info, symbol: "car.fill",
            label: L("leave.short"), value: L("leave.minutes", minutes),
            detail: L("leave.detail", e.title, e.place ?? "", minutes), genericDetail: L("generic.meeting"),
            url: e.link.map { ($0.appURL ?? $0.url).absoluteString }, startedAt: now), now: now)
        AppModel.shared.scheduleTick()
    }

    private func located(_ here: CLLocationCoordinate2D) {
        for e in TimeToLeave.candidates(AppModel.shared.meetings, now: Date()) {
            if let c = e.coordinate { eta(e.id, from: here, to: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)) }
            else if let c = places[e.place ?? ""] { eta(e.id, from: here, to: c) }
            else if let place = e.place { geocode(place) { TravelProvider.shared.eta(e.id, from: here, to: $0) } }
        }
    }

    private func geocode(_ place: String, then: @escaping @MainActor (CLLocationCoordinate2D) -> Void) {
        CLGeocoder().geocodeAddressString(place) { @Sendable marks, _ in
            guard let c = marks?.first?.location?.coordinate else { return }
            Task { @MainActor in TravelProvider.shared.places[place] = c; then(c) }
        }
    }

    private func eta(_ id: String, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) {
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        req.transportType = .automobile
        MKDirections(request: req).calculateETA { @Sendable r, _ in
            guard let t = r?.expectedTravelTime else { return }
            Task { @MainActor in
                TravelProvider.shared.travel[id] = t
                TravelProvider.shared.arm(id)
            }
        }
    }
}

extension TravelProvider: CLLocationManagerDelegate {
    // The manager is created on the main thread, so its delegate is called there.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        MainActor.assumeIsolated { TravelProvider.shared.located(c) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { TravelProvider.shared.refresh() }
    }
}
