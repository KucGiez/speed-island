import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct SpeedIslandWidgetBundle: WidgetBundle {
    var body: some Widget {
        SpeedLiveActivity()
        StartIslandControl()
    }
}

// MARK: - Live Activity

struct SpeedLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpeedAttributes.self) { context in
            LockScreenView(state: context.state, startedAt: context.attributes.startedAt, isStale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeading(state: state)
                        .dimmed(stale)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailing(state: state)
                        .dimmed(stale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(state: state, isStale: stale)
                }
            } compactLeading: {
                CompactLeading(state: state)
                    .dimmed(stale)
            } compactTrailing: {
                CompactTrailing(state: state)
                    .dimmed(stale)
            } minimal: {
                SingleSlotView(state: state)
                    .dimmed(stale)
            }
            .keylineTint(state.isHot ? thermalColor(state.thermal) : Color.green)
        }
        // Własny układ dla Apple Watch (Smart Stack) i CarPlay zamiast złożonego kompaktu.
        .supplementalActivityFamilies([.small])
    }
}

// MARK: - Kompakt i widok minimalny

/// iOS 27: Wyspa bywa zwężona (poziomo, iPhone 18 Pro z drugą aktywnością, iPhone Duo).
/// Na starszych systemach zawsze pełna szerokość.
private struct LimitedWidthReader<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        if #available(iOS 27.0, *) {
            LimitedWidthReader27(content: content)
        } else {
            content(false)
        }
    }
}

@available(iOS 27.0, *)
private struct LimitedWidthReader27<Content: View>: View {
    @Environment(\.isDynamicIslandLimitedInWidth) private var limited
    let content: (Bool) -> Content

    var body: some View { content(limited) }
}

/// Pełna szerokość (lewa strona kamery):
/// - Transfer: `↓ 84 KB/s`; przy „jednej stronie” stos `↓84K / ↑12K`
/// - Termika: `❄️`
/// - Oba: stos `↓84K / ↑12K`; przy „jednej stronie” `❄️` + stos
/// Zwężona: jedno pole mieszczące się w kółku 28 pt.
private struct CompactLeading: View {
    let state: SpeedAttributes.ContentState

    var body: some View {
        LimitedWidthReader { limited in
            if limited {
                SingleSlotView(state: state)
            } else {
                switch state.mode {
                case .transfer:
                    if state.oneSide {
                        SpeedStack(state: state)
                    } else {
                        SpeedLabel(symbol: "arrow.down", value: state.down, tint: .green)
                    }
                case .thermal:
                    ThermalIcon(raw: state.thermal, size: 17)
                case .both:
                    if state.oneSide {
                        HStack(spacing: 5) {
                            ThermalIcon(raw: state.thermal, size: 17)
                            SpeedStack(state: state)
                        }
                    } else {
                        SpeedStack(state: state)
                    }
                }
            }
        }
    }
}

/// Pełna szerokość (prawa strona kamery, przy baterii):
/// - Transfer: `↑ 12 KB/s`; przy „jednej stronie” pusto
/// - Termika: `OK`
/// - Oba: `❄️`; przy „jednej stronie” pusto
/// Pusty widok system ukrywa, więc Wyspa rośnie tylko w lewo.
private struct CompactTrailing: View {
    let state: SpeedAttributes.ContentState

    var body: some View {
        LimitedWidthReader { limited in
            if limited || (state.oneSide && state.mode != .thermal) {
                EmptyView()
            } else {
                switch state.mode {
                case .transfer:
                    SpeedLabel(symbol: "arrow.up", value: state.up, tint: .orange)
                case .thermal:
                    Text(thermalLabel(state.thermal))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(thermalColor(state.thermal))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                case .both:
                    ThermalIcon(raw: state.thermal, size: 18)
                }
            }
        }
    }
}

/// Oba kierunki jeden pod drugim: dwie linie po 12 pt mieszczą się w wysokości kompaktu (~37 pt).
private struct SpeedStack: View {
    let state: SpeedAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: -1) {
            StackLine(symbol: "arrow.down", value: state.down, tint: .green)
            StackLine(symbol: "arrow.up", value: state.up, tint: .orange)
        }
    }
}

private struct StackLine: View {
    let symbol: String
    let value: Double
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(tint)
            Text(formatSpeedMinimal(value))
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText(value: value))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Jedno pole (widok minimalny obok innych aplikacji, zwężona Wyspa): ikona termiki
/// albo przeważająca prędkość w kolorze kierunku (zielony ↓, pomarańczowy ↑).
private struct SingleSlotView: View {
    let state: SpeedAttributes.ContentState

    var body: some View {
        switch state.singleSlot {
        case .thermal:
            ThermalIcon(raw: state.thermal, size: 16)
        case .speed:
            Text(formatSpeedMinimal(state.dominantSpeed))
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(state.dominantIsDownload ? Color.green : Color.orange)
                .contentTransition(.numericText(value: state.dominantSpeed))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}

/// Strzałka + liczba + jednostka, np. „↓ 84 KB/s”.
private struct SpeedLabel: View {
    let symbol: String
    let value: Double
    let tint: Color

    var body: some View {
        let parts = speedCompactParts(value)
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text(parts.number)
                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText(value: value))
            Text(parts.unit)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

private struct ThermalIcon: View {
    let raw: Int
    let size: CGFloat

    var body: some View {
        Text(thermalIcon(raw))
            .font(.system(size: size))
            .contentTransition(.opacity)
    }
}

// MARK: - Rozwinięta Wyspa

private struct ExpandedLeading: View {
    let state: SpeedAttributes.ContentState

    var body: some View {
        switch state.mode {
        case .transfer, .both:
            ExpandedSpeed(title: "Pobieranie", symbol: "arrow.down", value: state.down, tint: .green, alignment: .leading)
        case .thermal:
            HStack(spacing: 6) {
                ThermalIcon(raw: state.thermal, size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Termika").font(.caption2.weight(.medium)).foregroundStyle(Color.secondary)
                    Text(thermalLabel(state.thermal))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(thermalColor(state.thermal))
                }
            }
        }
    }
}

private struct ExpandedTrailing: View {
    let state: SpeedAttributes.ContentState

    var body: some View {
        switch state.mode {
        case .transfer, .both:
            ExpandedSpeed(title: "Wysyłanie", symbol: "arrow.up", value: state.up, tint: .orange, alignment: .trailing)
        case .thermal:
            VStack(alignment: .trailing, spacing: 0) {
                Label("CPU", systemImage: "cpu").font(.caption2.weight(.medium)).foregroundStyle(Color.blue)
                Text(formatCPU(state.cpu))
                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
            }
        }
    }
}

private struct ExpandedSpeed: View {
    let title: String
    let symbol: String
    let value: Double
    let tint: Color
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)
            Text(formatSpeedFull(value))
                .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                .contentTransition(.numericText(value: value))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

private struct ExpandedBottom: View {
    let state: SpeedAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(spacing: 8) {
            DetailsRow(state: state, isStale: isStale)
            if !isStale {
                ModeButton(mode: state.mode)
            }
        }
        .padding(.top, 4)
    }
}

/// Szczegóły zależne od trybu; przy nieaktualnych danych jasny komunikat zamiast starych liczb.
private struct DetailsRow: View {
    let state: SpeedAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isStale {
                Label("Wstrzymane – otwórz aplikację", systemImage: "pause.circle.fill")
                    .foregroundStyle(Color.secondary)
            } else {
                switch state.mode {
                case .transfer:
                    Label(formatCPU(state.cpu), systemImage: "cpu")
                    Spacer(minLength: 0)
                    Totals(state: state)
                case .thermal:
                    Text("Stan termiczny systemu – iOS nie podaje °C")
                        .foregroundStyle(Color.secondary)
                case .both:
                    Label(formatCPU(state.cpu), systemImage: "cpu")
                    Text("\(thermalIcon(state.thermal)) \(thermalLabel(state.thermal))")
                        .foregroundStyle(thermalColor(state.thermal))
                    Spacer(minLength: 0)
                    Totals(state: state)
                }
            }
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

private struct Totals: View {
    let state: SpeedAttributes.ContentState

    var body: some View {
        Text("↓ \(formatBytes(state.downTotal))  ↑ \(formatBytes(state.upTotal))")
            .foregroundStyle(Color.secondary)
    }
}

/// Jedyny element interaktywny (zalecenie HIG): przełącza widok bez otwierania aplikacji.
private struct ModeButton: View {
    let mode: DisplayMode

    var body: some View {
        Button(intent: CycleDisplayModeIntent()) {
            Label("Widok: \(mode.title) → \(mode.next.title)", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Color.green)
    }
}

// MARK: - Ekran blokady, StandBy, Apple Watch, CarPlay

private struct LockScreenView: View {
    @Environment(\.activityFamily) private var family
    let state: SpeedAttributes.ContentState
    let startedAt: Date
    let isStale: Bool

    var body: some View {
        if family == .small {
            SmallView(state: state, isStale: isStale)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    ExpandedLeading(state: state)
                    Spacer()
                    ExpandedTrailing(state: state)
                }
                .dimmed(isStale)
                DetailsRow(state: state, isStale: isStale)
                HStack {
                    Text("Sesja od \(startedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    if !isStale {
                        ModeButton(mode: state.mode)
                            .fixedSize()
                    }
                }
            }
            .foregroundStyle(Color.white)
            .padding(14)
        }
    }
}

/// Apple Watch Smart Stack i CarPlay: duże, czytelne wartości, bez przycisków
/// (CarPlay wyłącza elementy interaktywne).
private struct SmallView: View {
    let state: SpeedAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(spacing: 10) {
            if state.mode != .transfer {
                ThermalIcon(raw: state.thermal, size: 26)
            }
            if state.mode != .thermal {
                VStack(alignment: .leading, spacing: 2) {
                    SpeedLabel(symbol: "arrow.down", value: state.down, tint: .green)
                    SpeedLabel(symbol: "arrow.up", value: state.up, tint: .orange)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(thermalLabel(state.thermal))
                        .font(.headline)
                        .foregroundStyle(thermalColor(state.thermal))
                    Text("CPU \(formatCPU(state.cpu))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .dimmed(isStale)
        .padding(8)
    }
}

private extension View {
    func dimmed(_ isStale: Bool) -> some View {
        opacity(isStale ? 0.5 : 1)
    }
}

// MARK: - Centrum sterowania

/// Przycisk w Centrum sterowania (i na ekranie blokady / przycisku czynności przez kontrolki iOS 18+).
struct StartIslandControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SpeedIsland.Start") {
            ControlWidgetButton(action: StartIslandIntent()) {
                Label("SpeedIsland", systemImage: "gauge.with.dots.needle.67percent")
            }
        }
        .displayName("Licznik na Wyspie")
        .description("Uruchamia licznik transferu i termiki na Dynamicznej Wyspie.")
    }
}
