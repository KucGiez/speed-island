import CoreLocation

/// Utrzymuje proces przy życiu w tle, żeby Live Activity dostawała świeże dane.
///
/// iOS usypia aplikację kilka sekund po wyjściu z niej; bez tego Wyspa by zamarzła.
/// Używamy najtańszego trybu lokalizacji: dokładność 3 km (wieże komórkowe/Wi-Fi, bez GPS)
/// i maksymalny filtr odległości, więc zdarzeń praktycznie nie ma. Współrzędne są ignorowane.
/// Wystarcza zgoda „Podczas używania”; iOS pokazuje wtedy niebieski wskaźnik lokalizacji.
@MainActor
final class BackgroundKeepAlive: NSObject, CLLocationManagerDelegate {
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    private let manager = CLLocationManager()
    private(set) var isRunning = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = CLLocationDistanceMax
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    var isAuthorized: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Musi zostać wywołane, gdy aplikacja jest na pierwszym planie.
    func start() {
        guard isAuthorized, !isRunning else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isRunning = false
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        Task { @MainActor in self.onAuthorizationChange?(newStatus) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Celowo puste: lokalizacja służy wyłącznie do pracy w tle.
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Brak sygnału nie przeszkadza: proces dalej działa w tle.
    }
}
