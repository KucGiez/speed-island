import AppIntents

/// Skróty dostępne od razu po instalacji: Siri, Spotlight, aplikacja Skróty i przycisk czynności.
struct SpeedIslandShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartIslandIntent(),
            phrases: [
                "Uruchom licznik w \(.applicationName)",
                "Pokaż \(.applicationName) na Wyspie",
            ],
            shortTitle: "Uruchom licznik",
            systemImageName: "gauge.with.dots.needle.67percent"
        )
        AppShortcut(
            intent: StopIslandIntent(),
            phrases: ["Zatrzymaj licznik w \(.applicationName)"],
            shortTitle: "Zatrzymaj licznik",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: CycleDisplayModeIntent(),
            phrases: ["Zmień widok w \(.applicationName)"],
            shortTitle: "Zmień widok",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
