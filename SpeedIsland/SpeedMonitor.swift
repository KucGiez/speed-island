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
    }

    private(set) var reading = SpeedAttributes.ContentState.zero
    private(set) var history: [SpeedPoint] = []
    private(set) var islandActive = false
    private(set) var activitiesEnabled = true
    private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var lastError: String?
    private(set) var displayMode: DisplayMode = .both
    private(set) var overheatAlerts = true

    @ObservationIgnored private let engine = SamplingEngine()
    @ObservationIgnored private let island = IslandController()
    @ObservationIgnored private let keepAlive = BackgroundKeepAlive()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var uiVisible = false
    @ObservationIgnored private var locked = false
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
        reading.mode = displayMode
        locationStatus = keepAlive.status
        locked = !UIApplication.shared.isProtectedDataAvailable

        engine.handler = { [weak self] output in
            Task { @MainActor in self?.handle(output) }
        }
        island.onEnd = { [weak self] reason in
            self?.islandEnded(reason)
        }
        keepAlive.onAuthorizationChange = { [weak self] status in
            self?.authorizationChanged(status)
        }
        observeSystem()
        applyPolicy()
    }

    /// Wszystko zdarzeniowo, bez odpytywania: tryb oszczędzania, termika, blokada urządzenia.
    private func observeSystem() {
        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, _ action: @escaping @MainActor (SpeedMonitor) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    action(self)
                }
            })
        }
        observe(.NSProcessInfoPowerStateDidChange) { $0.engine.powerStateChanged() }
        // Zmiana termiki trafia na Wyspę od razu, także przy rzadkim próbkowaniu.
        observe(ProcessInfo.thermalStateDidChangeNotification) { $0.engine.sampleNow() }
        // Zablokowany telefon (z kodem) = ekran zwykle wyłączony: rzadsze próbkowanie.
        observe(UIApplication.protectedDataWillBecomeUnavailableNotification) { $0.setLocked(true) }
        observe(UIApplication.protectedDataDidBecomeAvailableNotification) { $0.setLocked(false) }
    }

    // MARK: - Cykl życia

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            uiVisible = true
            activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
            locationStatus = keepAlive.status
            locked = !UIApplication.shared.isProtectedDataAvailable
            island.adoptExisting()
            islandActive = island.isActive
            applyPolicy()
            engine.start()
            if islandActive {
                ensureBackgroundMode()
            } else if wantsIsland {
                startIsland()
            }
        case .background:
            uiVisible = false
            applyPolicy()
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
        island.setMode(mode)
        applyPolicy()
    }

    func setOverheatAlerts(_ enabled: Bool) {
        overheatAlerts = enabled
        defaults.set(enabled, forKey: Keys.overheatAlerts)
    }

    // MARK: - Wewnętrzne

    private func setLocked(_ value: Bool) {
        locked = value
        applyPolicy()
    }

    private func applyPolicy() {
        engine.setPolicy(.init(uiVisible: uiVisible, locked: locked, mode: displayMode))
    }

    private func startIsland() {
        lastError = nil
        activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        guard activitiesEnabled else {
            lastError = "Live Activities są wyłączone w Ustawieniach."
            return
        }
        do {
            engine.beginIslandSession()
            var initial = reading
            initial.downTotal = 0
            initial.upTotal = 0
            initial.mode = displayMode
            try island.start(initial: initial, staleAfter: 75)
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

    private func handle(_ output: SamplingEngine.Output) {
        // Stan obserwowany przez SwiftUI zmieniamy tylko na ekranie: w tle zero przeliczania widoków.
        if uiVisible {
            sequence += 1
            history.append(SpeedPoint(id: sequence, down: output.state.down, up: output.state.up))
            if history.count > Self.historyLength {
                history.removeFirst(history.count - Self.historyLength)
            }
            reading = output.state
        }
        if output.islandDue {
            island.push(output.state, staleAfter: output.staleAfter, overheatAlerts: overheatAlerts)
        }
    }
}
