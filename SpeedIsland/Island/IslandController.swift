import ActivityKit
import Foundation

/// Zarządza jedną Live Activity: start, przejęcie po restarcie aplikacji, aktualizacje,
/// zmiana trybu, alarm przegrzania i koniec. O tym, *kiedy* aktualizować, decyduje SamplingEngine.
@MainActor
final class IslandController {
    enum EndReason {
        /// Użytkownik zamknął aktywność (przesunięcie na ekranie blokady).
        case dismissedByUser
        /// System zakończył aktywność (np. limit 8 godzin).
        case endedBySystem
    }

    /// Minimalny odstęp między alarmami przegrzania.
    static let alertCooldown: TimeInterval = 10 * 60

    var onEnd: ((EndReason) -> Void)?
    var isActive: Bool { activity != nil }

    private var activity: Activity<SpeedAttributes>?
    private var watcher: Task<Void, Never>?
    private var staleAfter: TimeInterval = 75
    /// Najwyższy poziom termiczny, o którym już zaalarmowano w bieżącym epizodzie grzania.
    private var alertedLevel = 0
    private var lastAlert: TimeInterval = -.infinity

    /// Przejmuje aktywność, która przetrwała zamknięcie aplikacji; nadmiarowe kończy.
    func adoptExisting() {
        guard activity == nil else { return }
        let running = Activity<SpeedAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
        guard let first = running.first else { return }
        for extra in running.dropFirst() {
            Task { await extra.end(nil, dismissalPolicy: .immediate) }
        }
        attach(first)
    }

    func start(initial: SpeedAttributes.ContentState, staleAfter: TimeInterval) throws {
        adoptExisting()
        guard activity == nil else { return }
        self.staleAfter = staleAfter
        let created = try Activity.request(
            attributes: SpeedAttributes(startedAt: Date()),
            content: content(initial),
            pushType: nil
        )
        attach(created)
    }

    /// Wysyła aktualizację; przy wejściu na 🔥/💀 dołącza alarm (rozwinięcie Wyspy).
    func push(_ state: SpeedAttributes.ContentState, staleAfter: TimeInterval, overheatAlerts: Bool) {
        guard let activity else { return }
        self.staleAfter = staleAfter
        let alert = overheatAlerts ? overheatAlert(for: state.thermal) : nil
        let newContent = content(state)
        Task {
            if let alert {
                await activity.update(newContent, alertConfiguration: alert)
            } else {
                await activity.update(newContent)
            }
        }
    }

    /// Zmienia tryb od razu, na ostatnich znanych danych (bez czekania na kolejną próbkę).
    func setMode(_ mode: DisplayMode) {
        guard let activity else { return }
        var state = activity.content.state
        guard state.mode != mode else { return }
        state.mode = mode
        let newContent = content(state)
        Task { await activity.update(newContent) }
    }

    func stop() {
        guard let current = activity else { return }
        detach()
        Task { await current.end(nil, dismissalPolicy: .immediate) }
    }

    // MARK: - Wewnętrzne

    private func content(_ state: SpeedAttributes.ContentState) -> ActivityContent<SpeedAttributes.ContentState> {
        ActivityContent(state: state, staleDate: Date().addingTimeInterval(staleAfter))
    }

    /// Alarm (rozwinięcie Wyspy, podświetlenie ekranu) tylko przy wejściu na 🔥 albo 💀,
    /// raz na epizod i nie częściej niż co 10 minut. Spadek do ❄️/🌴 kończy epizod.
    private func overheatAlert(for thermal: Int) -> AlertConfiguration? {
        guard thermal >= 2 else {
            alertedLevel = 0
            return nil
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard thermal > alertedLevel, now - lastAlert >= Self.alertCooldown else { return nil }
        alertedLevel = thermal
        lastAlert = now
        if thermal >= 3 {
            return AlertConfiguration(
                title: "💀 iPhone jest przegrzany",
                body: "System ogranicza wydajność. Odłóż telefon i zamknij ciężkie aplikacje.",
                sound: .default
            )
        }
        return AlertConfiguration(
            title: "🔥 iPhone się grzeje",
            body: "Stan termiczny: gorąco. Warto odciążyć telefon.",
            sound: .default
        )
    }

    private func attach(_ newActivity: Activity<SpeedAttributes>) {
        activity = newActivity
        watcher = Task { [weak self] in
            for await state in newActivity.activityStateUpdates {
                switch state {
                case .dismissed:
                    self?.finish(newActivity, .dismissedByUser)
                    return
                case .ended:
                    self?.finish(newActivity, .endedBySystem)
                    return
                default:
                    continue
                }
            }
        }
    }

    private func finish(_ ended: Activity<SpeedAttributes>, _ reason: EndReason) {
        guard activity?.id == ended.id else { return }
        detach()
        onEnd?(reason)
    }

    private func detach() {
        watcher?.cancel()
        watcher = nil
        activity = nil
    }
}
