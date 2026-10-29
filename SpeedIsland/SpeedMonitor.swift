import ActivityKit
import CoreLocation
import Observation
import SwiftUI

struct SpeedPoint: Identifiable {
    let id: Int
    let down: Double
    let up: Double
}

/// Stan aplikacji: łączy silnik próbkowania, Live Activity i pracę w tle.
@MainActor
@Observable
final class SpeedMonitor {
    static let historyLength = 60
    private static let wantsIslandKey = "wantsIsland"

    private(set) var reading = SpeedAttributes.ContentState.zero
    private(set) var history: [SpeedPoint] = []
    private(set) var islandActive = false
    private(set) var activitiesEnabled = true
    private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var lastError: String?

    @ObservationIgnored private let engine = SamplingEngine()
    @ObservationIgnored private let island = IslandController()
    @ObservationIgnored private let keepAlive = BackgroundKeepAlive()
    @ObservationIgnored private var buffer: [SpeedPoint] = []
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var uiVisible = false
    @ObservationIgnored private var powerObserver: NSObjectProtocol?

    /// Czy użytkownik chce mieć licznik na Wyspie. Po limicie 8 h albo zamknięciu aplikacji
    /// licznik wraca sam przy następnym otwarciu; wyłącza go tylko użytkownik.
    private var wantsIsland: Bool {
        get { UserDefaults.standard.bool(forKey: Self.wantsIslandKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.wantsIslandKey) }
    }

    init() {
        engine.handler = { [weak self] state in
            Task { @MainActor in self?.handle(state) }
        }
        island.onEnd = { [weak self] reason in
            self?.islandEnded(reason)
        }
        keepAlive.onAuthorizationChange = { [weak self] status in
            self?.authorizationChanged(status)
        }
        locationStatus = keepAlive.status
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyPowerMode() }
        }
        applyPowerMode()
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
            engine.start()
            if islandActive {
                ensureBackgroundMode()
            } else if wantsIsland {
                startIsland()
            }
        case .background:
            uiVisible = false
            // Bez Wyspy w tle nic nie liczymy: zero kosztu energii.
            if !island.isActive { engine.stop() }
        default:
            break
        }
    }

    // MARK: - Akcje użytkownika

    func toggleIsland() {
        if islandActive {
            wantsIsland = false
            stopIsland()
        } else {
            wantsIsland = true
            startIsland()
        }
    }

    func requestBackgroundPermission() {
        keepAlive.requestAuthorization()
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
            try island.start(initial: initial)
            islandActive = true
            engine.start()
            ensureBackgroundMode()
        } catch {
            lastError = "Nie udało się uruchomić licznika: \(error.localizedDescription)"
        }
    }

    private func stopIsland() {
        island.stop()
        islandActive = false
        keepAlive.stop()
        if !uiVisible { engine.stop() }
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

    private func applyPowerMode() {
        engine.setInterval(ProcessInfo.processInfo.isLowPowerModeEnabled ? 2 : 1)
    }

    private func handle(_ state: SpeedAttributes.ContentState) {
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
        island.push(state)
    }
}
