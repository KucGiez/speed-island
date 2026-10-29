import ActivityKit
import CoreLocation
import Observation
import SwiftUI

struct SpeedPoint: Identifiable {
    let id: Int
    let down: Double
    let up: Double
}

/// Stan aplikacji: łączy silnik próbkowania, Live Activity, pracę w tle i intencje (Wyspa, skróty, Centrum sterowania).
@MainActor
@Observable
final class SpeedMonitor {
    /// Jeden egzemplarz na proces: intencje mogą przyjść, zanim powstanie jakakolwiek scena.
    static let shared = SpeedMonitor()
    static let historyLength = 60

    private enum Keys {
        static let wantsIsland = "wantsIsland"
        static let displayMode = "displayMode"
        static let overheatAlerts = "overheatAlerts"
        static let oneSide = "oneSide"
    }

    private(set) var reading = SpeedAttributes.ContentState.zero
    private(set) var history: [SpeedPoint] = []
    private(set) var islandActive = false
    private(set) var activitiesEnabled = true
    private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var lastError: String?
    private(set) var displayMode: DisplayMode = .both
    private(set) var overheatAlerts = true
    private(set) var oneSide = false

    @ObservationIgnored private let engine = SamplingEngine()
    @ObservationIgnored private let island = IslandController()
    @ObservationIgnored private let keepAlive = BackgroundKeepAlive()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var buffer: [SpeedPoint] = []
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var uiVisible = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// Czy użytkownik chce mieć licznik na Wyspie. Po limicie 8 h albo zamknięciu aplikacji
    /// licznik wraca sam przy następnym otwarciu; wyłącza go tylko użytkownik.
    private var wantsIsland: Bool {
        get { defaults.bool(forKey: Keys.wantsIsland) }
        set { defaults.set(newValue, forKey: Keys.wantsIsland) }
    }

    private init() {
        displayMode = (defaults.object(forKey: Keys.displayMode) as? Int).flatMap(DisplayMode.init(rawValue:)) ?? .both
        overheatAlerts = (defaults.object(forKey: Keys.overheatAlerts) as? Bool) ?? true
        oneSide = defaults.bool(forKey: Keys.oneSide)
        reading.mode = displayMode
        reading.oneSide = oneSide
        locationStatus = keepAlive.status

        engine.handler = { [weak self] state in
            Task { @MainActor in self?.handle(state) }
        }
        island.onEnd = { [weak self] reason in
            self?.islandEnded(reason)
        }
        keepAlive.onAuthorizationChange = { [weak self] status in
            self?.authorizationChanged(status)
        }

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateInterval() }
        })
        // Zmiana termiki trafia na Wyspę od razu, także przy rzadkim próbkowaniu w trybie „Termika”.
        observers.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.engine.sampleNow() }
        })
        updateInterval()
    }

    // MARK: - Cykl życia

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            uiVisible = true
            history = buffer
            activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
            locationStatus = keepAlive.status
            island.adoptExisting()
            islandActive = island.isActive
            updateInterval()
            engine.start()
            if islandActive {
                ensureBackgroundMode()
            } else if wantsIsland {
                startIsland()
            }
        case .background:
            uiVisible = false
            updateInterval()
            // Bez Wyspy w tle nic nie liczymy: zero kosztu energii.
            if !island.isActive { engine.stop() }
        default:
            break
        }
    }

    // MARK: - Akcje użytkownika (aplikacja, przyciski Wyspy, skróty, Centrum sterowania)

    func toggleIsland() {
        islandActive ? requestStop() : requestStart()
    }

    /// Z intencji ze `openAppWhenRun`: aplikacja zaraz będzie aktywna, a start nastąpi w `scenePhaseChanged`.
    func requestStart() {
        wantsIsland = true
        if uiVisible, !island.isActive { startIsland() }
    }

    func requestStop() {
        wantsIsland = false
        island.adoptExisting()
        island.stop()
        islandActive = false
        keepAlive.stop()
        if !uiVisible { engine.stop() }
    }

    func cycleDisplayMode() {
        setDisplayMode(displayMode.next)
    }

    func setDisplayMode(_ mode: DisplayMode) {
        displayMode = mode
        reading.mode = mode
        defaults.set(mode.rawValue, forKey: Keys.displayMode)
        island.adoptExisting()
        island.setPresentation(mode: mode, oneSide: oneSide)
        updateInterval()
    }

    func setOneSide(_ enabled: Bool) {
        oneSide = enabled
        reading.oneSide = enabled
        defaults.set(enabled, forKey: Keys.oneSide)
        island.adoptExisting()
        island.setPresentation(mode: displayMode, oneSide: enabled)
    }

    func setOverheatAlerts(_ enabled: Bool) {
        overheatAlerts = enabled
        defaults.set(enabled, forKey: Keys.overheatAlerts)
    }

    // MARK: - Wewnętrzne

    private func startIsland() {
        lastError = nil
        activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        guard activitiesEnabled else {
            lastError = "Live Activities są wyłączone w Ustawieniach."
            return
        }
        do {
            engine.resetTotals()
            var initial = reading
            initial.downTotal = 0
            initial.upTotal = 0
            initial.mode = displayMode
            initial.oneSide = oneSide
            try island.start(initial: initial)
            islandActive = true
            engine.start()
            ensureBackgroundMode()
        } catch {
            lastError = "Nie udało się uruchomić licznika: \(error.localizedDescription)"
        }
    }

    private func ensureBackgroundMode() {
        switch keepAlive.status {
        case .notDetermined:
            keepAlive.requestAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            keepAlive.start()
        default:
            break
        }
    }

    private func islandEnded(_ reason: IslandController.EndReason) {
        if reason == .dismissedByUser { wantsIsland = false }
        islandActive = false
        keepAlive.stop()
        if !uiVisible { engine.stop() }
    }

    private func authorizationChanged(_ status: CLAuthorizationStatus) {
        locationStatus = status
        if island.isActive, uiVisible { ensureBackgroundMode() }
    }

    /// 1 s na ekranie i dla transferu; 5 s w tle, gdy Wyspa pokazuje tylko termikę
    /// (zmiany termiki i tak przychodzą od razu przez powiadomienie); 2 s w trybie oszczędzania energii.
    private func updateInterval() {
        let base: TimeInterval = ProcessInfo.processInfo.isLowPowerModeEnabled ? 2 : 1
        let thermalOnlyInBackground = !uiVisible && displayMode == .thermal
        engine.setInterval(thermalOnlyInBackground ? 5 : base)
    }

    private func handle(_ sample: SpeedAttributes.ContentState) {
        var state = sample
        state.mode = displayMode
        state.oneSide = oneSide
        sequence += 1
        buffer.append(SpeedPoint(id: sequence, down: state.down, up: state.up))
        if buffer.count > Self.historyLength {
            buffer.removeFirst(buffer.count - Self.historyLength)
        }
        // W tle nie dotykamy stanu obserwowanego przez SwiftUI: brak zbędnego przeliczania widoków.
        if uiVisible {
            reading = state
            history = buffer
        }
        island.push(state, overheatAlerts: overheatAlerts)
    }
}
