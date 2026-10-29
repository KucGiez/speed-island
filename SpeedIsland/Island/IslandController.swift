import ActivityKit
import Foundation

/// Zarządza jedną Live Activity: start, przejęcie po restarcie aplikacji, oszczędne aktualizacje, koniec.
@MainActor
final class IslandController {
    enum EndReason {
        /// Użytkownik zamknął aktywność (przesunięcie na ekranie blokady).
        case dismissedByUser
        /// System zakończył aktywność (np. limit 8 godzin).
        case endedBySystem
    }

    /// Wymuszenie aktualizacji, nawet gdy tekst się nie zmienił (podtrzymanie „świeżości”).
    static let heartbeat: TimeInterval = 15
    /// Po tym czasie bez aktualizacji widget pokaże stan „wstrzymane” zamiast nieaktualnych liczb.
    static let staleAfter: TimeInterval = 30

    var onEnd: ((EndReason) -> Void)?
    var isActive: Bool { activity != nil }

    private var activity: Activity<SpeedAttributes>?
    private var watcher: Task<Void, Never>?
    private var lastKey = ""
    private var lastPush: TimeInterval = 0

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

    func start(initial: SpeedAttributes.ContentState) throws {
        adoptExisting()
        guard activity == nil else { return }
        let content = ActivityContent(state: initial, staleDate: Date().addingTimeInterval(Self.staleAfter))
        let created = try Activity.request(
            attributes: SpeedAttributes(startedAt: Date()),
            content: content,
            pushType: nil
        )
        attach(created)
    }

    /// Wysyła aktualizację tylko wtedy, gdy zmieni się to, co widać na Wyspie,
    /// albo minął heartbeat. Przy bezczynnej sieci daje to 4 aktualizacje na minutę zamiast 60.
    func push(_ state: SpeedAttributes.ContentState) {
        guard let activity else { return }
        let key = Self.visibleKey(state)
        let now = ProcessInfo.processInfo.systemUptime
        guard key != lastKey || now - lastPush >= Self.heartbeat else { return }
        lastKey = key
        lastPush = now
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(Self.staleAfter))
        Task { await activity.update(content) }
    }

    func stop() {
        guard let current = activity else { return }
        detach()
        Task { await current.end(nil, dismissalPolicy: .immediate) }
    }

    private func attach(_ newActivity: Activity<SpeedAttributes>) {
        activity = newActivity
        lastKey = ""
        lastPush = 0
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

    private static func visibleKey(_ s: SpeedAttributes.ContentState) -> String {
        let down = speedCompactParts(s.down)
        let up = speedCompactParts(s.up)
        return "\(down.number)\(down.unit)|\(up.number)\(up.unit)|\(formatCPU(s.cpu))|\(s.thermal)"
    }
}
