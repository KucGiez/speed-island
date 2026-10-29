import Foundation

/// Próbkuje sieć i CPU na własnej kolejce (QoS utility), nigdy na wątku głównym.
/// Cały stan jest ograniczony do `queue`, stąd `@unchecked Sendable`.
final class SamplingEngine: @unchecked Sendable {
    typealias Handler = @Sendable (SpeedAttributes.ContentState) -> Void

    /// Ustawiane raz, przed pierwszym `start()`.
    var handler: Handler?

    private let queue = DispatchQueue(label: "speedisland.sampling", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var interval: TimeInterval = 1
    private var network = NetworkSampler()
    private var cpu = CPULoadSampler()
    private var lastUptime: TimeInterval = 0
    private var downTotal: UInt64 = 0
    private var upTotal: UInt64 = 0

    /// Startuje próbkowanie; wywołanie przy działającym silniku nic nie robi.
    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            network.reset()
            cpu.reset()
            _ = network.sample()
            _ = cpu.sample()
            lastUptime = ProcessInfo.processInfo.systemUptime

            let t = DispatchSource.makeTimerSource(queue: queue)
            t.setEventHandler { [weak self] in self?.tick() }
            schedule(t)
            t.resume()
            timer = t
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    /// Zmienia odstęp próbkowania w locie (np. 2 s w trybie oszczędzania energii).
    func setInterval(_ seconds: TimeInterval) {
        queue.async { [self] in
            guard interval != seconds else { return }
            interval = seconds
            if let timer { schedule(timer) }
        }
    }

    func resetTotals() {
        queue.async { [self] in
            downTotal = 0
            upTotal = 0
        }
    }

    /// Natychmiastowa próbka poza harmonogramem (np. po zmianie stanu termicznego).
    func sampleNow() {
        queue.async { [self] in
            guard timer != nil else { return }
            tick()
        }
    }

    /// 10% tolerancji pozwala systemowi łączyć wybudzenia z innymi (oszczędność energii).
    private func schedule(_ t: DispatchSourceTimer) {
        t.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(Int(interval * 100))
        )
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        // Prędkość liczona z faktycznie upłyniętego czasu: po uśpieniu procesu wyjdzie średnia, nie skok.
        let elapsed = max(now - lastUptime, 0.05)
        lastUptime = now

        let bytes = network.sample()
        downTotal &+= bytes.rx
        upTotal &+= bytes.tx

        let state = SpeedAttributes.ContentState(
            down: Double(bytes.rx) / elapsed,
            up: Double(bytes.tx) / elapsed,
            cpu: cpu.sample(),
            thermal: ProcessInfo.processInfo.thermalState.rawValue,
            downTotal: downTotal,
            upTotal: upTotal,
            mode: .both, // tryb i układ nadaje SpeedMonitor
            oneSide: false
        )
        handler?(state)
    }
}
