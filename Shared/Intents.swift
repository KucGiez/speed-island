import AppIntents

// Intencje są kompilowane w aplikacji i w rozszerzeniu widgetu (przyciski Wyspy, Centrum sterowania).
// System wykonuje je zawsze w procesie aplikacji, dlatego logika jest tylko pod flagą SPEEDISLAND_APP.

/// Przycisk na rozwiniętej Wyspie i ekranie blokady: Transfer → Termika → Oba.
struct CycleDisplayModeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Zmień widok licznika"
    static let description = IntentDescription("Przełącza Wyspę między transferem, termiką i obydwoma.")

    func perform() async throws -> some IntentResult {
        #if SPEEDISLAND_APP
        await SpeedMonitor.shared.cycleDisplayMode()
        #endif
        return .result()
    }
}

/// Start wymaga pierwszego planu (praca w tle i Live Activity), dlatego otwiera aplikację.
struct StartIslandIntent: AppIntent {
    static let title: LocalizedStringResource = "Uruchom licznik na Wyspie"
    static let description = IntentDescription("Pokazuje transfer i termikę na Dynamicznej Wyspie.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        #if SPEEDISLAND_APP
        await SpeedMonitor.shared.requestStart()
        #endif
        return .result()
    }
}

/// Zatrzymanie działa w tle, bez otwierania aplikacji.
struct StopIslandIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Zatrzymaj licznik na Wyspie"
    static let description = IntentDescription("Usuwa licznik z Dynamicznej Wyspy i wyłącza pracę w tle.")

    func perform() async throws -> some IntentResult {
        #if SPEEDISLAND_APP
        await SpeedMonitor.shared.requestStop()
        #endif
        return .result()
    }
}
