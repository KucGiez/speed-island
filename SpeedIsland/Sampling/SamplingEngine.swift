import Foundation

/// Próbkuje sieć, CPU i termikę na własnej kolejce (QoS utility) i decyduje,
/// kiedy obudzić wątek główny oraz kiedy Wyspa naprawdę potrzebuje aktualizacji.
///
/// Zasady (Apple: „Reducing your app's battery use”, „Responding to power notifications”):
/// - wybudzaj się tylko tak często, jak wymaga tego to, co widać,
/// - aktualizuj Live Activity tylko przy nowej treści, a „świeżość” podtrzymuj rzadkim heartbeatem,
/// - w trybie oszczędzania energii i przy wysokiej temperaturze ogranicz odświeżanie.
///
/// Cały stan jest ograniczony do `queue`, stąd `@unchecked Sendable`.
final class SamplingEngine: @unchecked Sendable {
    /// Okoliczności, od których zależy rytm próbkowania (ustawia SpeedMonitor).
    struct Policy: Equatable, Sendable {
        /// Aplikacja na ekranie: wykres i liczby co 1 s.
        var uiVisible = false
        /// Urządzenie zablokowane (dane chronione niedostępne): ekran zwykle wyłączony.
        var locked = false
        /// Ekran zgaszony (nieoficjalny sygnał `hasBlankedScreen`, o ile działa i jest włączony).
        var screenOff = false
        var mode: DisplayMode = .both
    }

    struct Output: Sendable {
        let state: SpeedAttributes.ContentState
        /// Wyspa wymaga aktualizacji: zmieniła się widoczna treść albo minął heartbeat.
        let islandDue: Bool
        /// Po jakim czasie bez aktualizacji widget ma pokazać „Wstrzymane”.
        let staleAfter: TimeInterval
    }

    typealias Handler = @Sendable (Output) -> Void

    /// Ustawiane raz, przed pierwszym `start()`.
    var handler: Handler?

    /// Poniżej tej prędkości (w obu kierunkach) sieć uznajemy za bezczynną.
    private static let idleThreshold = 1024.0
    /// Tyle bezczynnych próbek z rzędu przełącza na rzadsze próbkowanie.
    private static let idleSamplesForBackoff = 5

    private let queue = DispatchQueue(label: "speedisland.sampling", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var scheduledInterval: TimeInterval = 0
    private var policy = Policy()
    private var network = NetworkSampler()
    private var cpu = CPULoadSampler()
    private var lastCPU: Double?
    private var lastUptime: TimeInterval = 0
    private var downTotal: UInt64 = 0
    private var upTotal: UInt64 = 0
    private var idleStreak = 0
    private var lastIslandKey = ""
    private var lastIslandEmit: TimeInterval = -.infinity

    // MARK: - Sterowanie

    /// Startuje próbkowanie; wywołanie przy działającym silniku nic nie robi.
    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            network.reset()
            cpu.reset()
            _ = network.sample()
            _ = cpu.sample()
            lastUptime = ProcessInfo.processInfo.systemUptime
            idleStreak = 0

            let t = DispatchSource.makeTimerSource(queue: queue)
            t.setEventHandler { [weak self] in self?.tick() }
            timer = t
            reschedule(force: true)
            t.resume()
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    func setPolicy(_ newPolicy: Policy) {
        queue.async { [self] in
            guard newPolicy != policy else { return }
            let unlocked = policy.locked && !newPolicy.locked
            let screenOn = policy.screenOff && !newPolicy.screenOff
            let becameVisible = !policy.uiVisible && newPolicy.uiVisible
            policy = newPolicy
            reschedule()
            // Po zapaleniu ekranu, odblokowaniu i otwarciu aplikacji Wyspa i ekran mają od razu świeże dane.
            if timer != nil, unlocked || screenOn || becameVisible { tick() }
        }
    }

    /// Zmiana trybu oszczędzania energii: przelicz rytm.
    func powerStateChanged() {
        queue.async { [self] in reschedule() }
    }

    /// Natychmiastowa próbka poza harmonogramem (np. po zmianie stanu termicznego).
    func sampleNow() {
        queue.async { [self] in
            guard timer != nil else { return }
            tick()
        }
    }

    /// Nowa sesja Wyspy: sumy od zera i pierwsza próbka idzie na Wyspę bez względu na klucz.
    func beginIslandSession() {
        queue.async { [self] in
            downTotal = 0
            upTotal = 0
            lastIslandKey = ""
            lastIslandEmit = -.infinity
        }
    }

    // MARK: - Rytm

    /// Heartbeat podtrzymuje „świeżość” Wyspy i odświeża CPU oraz sumy, które nie wchodzą do klucza.
    /// Przy zgaszonym ekranie 120 s: na Always-On (ekran blokady przyciemniony) Wyspa nie pokaże
    /// „Wstrzymane”, a aplikacja budzi się 30 razy na godzinę zamiast 360.
    private var heartbeat: TimeInterval {
        if policy.screenOff { return 120 }
        return policy.locked ? 60 : 30
    }

    private func desiredInterval() -> TimeInterval {
        var seconds: TimeInterval
        if policy.uiVisible {
            seconds = 1
        } else if policy.mode == .thermal || policy.screenOff {
            // Termika przychodzi zdarzeniem (thermalStateDidChange), a przy zgaszonym ekranie
            // nikt nie patrzy na liczby: timer tylko podtrzymuje Wyspę.
            seconds = heartbeat
        } else if policy.locked {
            seconds = 10
        } else {
            seconds = idleStreak >= Self.idleSamplesForBackoff ? 3 : 1
        }
        let info = ProcessInfo.processInfo
        if info.isLowPowerModeEnabled { seconds *= 2 }
        if !policy.uiVisible, info.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
            seconds *= 2
        }
        return seconds
    }

    private func reschedule(force: Bool = false) {
        guard let timer else { return }
        let seconds = desiredInterval()
        guard force || seconds != scheduledInterval else { return }
        scheduledInterval = seconds
        // Tolerancja pozwala systemowi łączyć wybudzenia z innymi: 10% na ekranie, 25% w tle.
        let tolerance = policy.uiVisible ? 0.10 : 0.25
        timer.schedule(
            deadline: .now() + seconds,
            repeating: seconds,
            leeway: .milliseconds(Int(seconds * 1000 * tolerance))
        )
    }

    // MARK: - Próbka

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        // Prędkość z faktycznie upłyniętego czasu: przy rzadkim próbkowaniu wychodzi średnia, nie skok.
        let elapsed = max(now - lastUptime, 0.05)
        lastUptime = now

        let bytes = network.sample()
        downTotal &+= bytes.rx
        upTotal &+= bytes.tx
        let down = Double(bytes.rx) / elapsed
        let up = Double(bytes.tx) / elapsed
        idleStreak = down < Self.idleThreshold && up < Self.idleThreshold ? idleStreak + 1 : 0

        let heartbeatDue = now - lastIslandEmit >= heartbeat
        // CPU tylko wtedy, gdy ktoś je zobaczy; w tle wynik to średnia z całego okna heartbeatu.
        if policy.uiVisible || heartbeatDue {
            lastCPU = cpu.sample() ?? lastCPU
        }

        let state = SpeedAttributes.ContentState(
            down: down,
            up: up,
            cpu: lastCPU,
            thermal: ProcessInfo.processInfo.thermalState.rawValue,
            downTotal: downTotal,
            upTotal: upTotal,
            mode: policy.mode
        )

        let key = state.islandKey
        let islandDue = heartbeatDue || key != lastIslandKey
        if islandDue {
            lastIslandKey = key
            lastIslandEmit = now
        }

        reschedule()

        // Wątek główny budzimy tylko wtedy, gdy jest coś do pokazania.
        guard islandDue || policy.uiVisible else { return }
        handler?(Output(
            state: state,
            islandDue: islandDue,
            staleAfter: max(heartbeat, scheduledInterval) * 2.5
        ))
    }
}
