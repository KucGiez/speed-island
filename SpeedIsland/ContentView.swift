import Charts
import CoreLocation
import SwiftUI

struct ContentView: View {
    @Environment(SpeedMonitor.self) private var monitor

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SpeedHeader(reading: monitor.reading)
                    SpeedChart(history: monitor.history)
                    StatsCard(reading: monitor.reading)
                    IslandCard()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("SpeedIsland")
        }
    }
}

// MARK: - Karty

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}

private struct SpeedHeader: View {
    let reading: SpeedAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            SpeedTile(title: "Pobieranie", symbol: "arrow.down", value: reading.down, tint: .green)
            SpeedTile(title: "Wysyłanie", symbol: "arrow.up", value: reading.up, tint: .orange)
        }
    }
}

private struct SpeedTile: View {
    let title: String
    let symbol: String
    let value: Double
    let tint: Color

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tint)
                Text(formatSpeedFull(value))
                    .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText(value: value))
                    .animation(.snappy, value: value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

private struct SpeedChart: View {
    let history: [SpeedPoint]

    var body: some View {
        let last = history.last?.id ?? 0
        let first = max(0, last - (SpeedMonitor.historyLength - 1))
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ostatnia minuta")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Chart(history) { point in
                    AreaMark(
                        x: .value("Czas", point.id),
                        y: .value("Pobieranie", point.down)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.green.opacity(0.15))

                    LineMark(
                        x: .value("Czas", point.id),
                        y: .value("Prędkość", point.down),
                        series: .value("Kierunek", "Pobieranie")
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.green)

                    LineMark(
                        x: .value("Czas", point.id),
                        y: .value("Prędkość", point.up),
                        series: .value("Kierunek", "Wysyłanie")
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.orange)
                }
                .chartXScale(domain: first...max(first + SpeedMonitor.historyLength - 1, last))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(formatSpeedFull(v))
                            }
                        }
                    }
                }
                .frame(height: 170)
            }
        }
    }
}

private struct StatsCard: View {
    let reading: SpeedAttributes.ContentState

    var body: some View {
        Card {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow {
                    Stat(title: "CPU", value: formatCPU(reading.cpu), symbol: "cpu", tint: .blue)
                    Stat(
                        title: "Termika",
                        value: "\(thermalIcon(reading.thermal)) \(thermalLabel(reading.thermal))",
                        symbol: "thermometer.medium",
                        tint: thermalColor(reading.thermal)
                    )
                }
                GridRow {
                    Stat(title: "Pobrano", value: formatBytes(reading.downTotal), symbol: "arrow.down.circle", tint: .green)
                    Stat(title: "Wysłano", value: formatBytes(reading.upTotal), symbol: "arrow.up.circle", tint: .orange)
                }
            }
        }
    }
}

private struct Stat: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sterowanie Wyspą

private struct IslandCard: View {
    @Environment(SpeedMonitor.self) private var monitor
    @Environment(\.openURL) private var openURL

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    monitor.toggleIsland()
                } label: {
                    Label(
                        monitor.islandActive ? "Wyłącz licznik na Wyspie" : "Pokaż na Wyspie",
                        systemImage: monitor.islandActive ? "stop.circle.fill" : "play.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(monitor.islandActive ? Color.red : Color.accentColor)
                .controlSize(.large)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Na Wyspie")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Picker("Na Wyspie", selection: Binding(
                        get: { monitor.displayMode },
                        set: { monitor.setDisplayMode($0) }
                    )) {
                        ForEach(DisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Toggle(isOn: Binding(
                    get: { monitor.overheatAlerts },
                    set: { monitor.setOverheatAlerts($0) }
                )) {
                    Label("Alarm przy przegrzaniu 🔥 💀", systemImage: "bell.badge")
                        .font(.subheadline)
                }

                Toggle(isOn: Binding(
                    get: { monitor.screenSignal },
                    set: { monitor.setScreenSignal($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Oszczędzaj przy zgaszonym ekranie", systemImage: "moon.zzz")
                            .font(.subheadline)
                        Text(screenSignalStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                backgroundStatus

                if !monitor.activitiesEnabled {
                    Notice(
                        symbol: "exclamationmark.triangle.fill",
                        tint: .orange,
                        text: "Live Activities są wyłączone: Ustawienia → SpeedIsland → Live Activities."
                    )
                    settingsButton
                }

                if let error = monitor.lastError {
                    Notice(symbol: "xmark.octagon.fill", tint: .red, text: error)
                }

                Text("Termika: ❄️ OK, 🌴 ciepło, 🔥 gorąco, 💀 krytycznie (iOS nie podaje °C). Gdy działają aktywności innych aplikacji, SpeedIsland pokazuje jedno pole: prędkość, a przy przegrzaniu ikonę. Live Activity trwa maksymalnie 8 godzin; po otwarciu aplikacji wraca sama.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var backgroundStatus: some View {
        switch monitor.locationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            Notice(
                symbol: "checkmark.circle.fill",
                tint: .green,
                text: "Praca w tle aktywna. Niebieski wskaźnik lokalizacji oznacza, że licznik działa; współrzędne są ignorowane."
            )
        case .notDetermined:
            Notice(
                symbol: "location.circle",
                tint: .blue,
                text: "Przy starcie licznika zapytam o lokalizację „Podczas używania”. Bez niej iOS uśpi licznik kilka sekund po wyjściu z aplikacji."
            )
        default:
            Notice(
                symbol: "exclamationmark.triangle.fill",
                tint: .orange,
                text: "Brak zgody na lokalizację: licznik na Wyspie zatrzyma się po wyjściu z aplikacji."
            )
            settingsButton
        }
    }

    private var screenSignalStatus: String {
        guard monitor.screenSignal else {
            return "Wyłączone: przy zablokowanym telefonie pomiar co 10 s."
        }
        if monitor.screenSignalSeen {
            return "Sygnał działa: przy zgaszonym ekranie odświeżanie co 2 min."
        }
        return "Nieoficjalny sygnał iOS. Zgaś i zapal ekran, żeby sprawdzić, czy działa."
    }

    private var settingsButton: some View {
        Button("Otwórz Ustawienia") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        }
        .font(.subheadline.weight(.medium))
    }
}

private struct Notice: View {
    let symbol: String
    let tint: Color
    let text: String

    var body: some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
    }
}
