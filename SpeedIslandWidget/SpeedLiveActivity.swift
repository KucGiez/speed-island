import ActivityKit
import SwiftUI
import WidgetKit

@main
struct SpeedIslandWidgetBundle: WidgetBundle {
    var body: some Widget {
        SpeedLiveActivity()
    }
}

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
                    ExpandedSpeed(title: "Pobieranie", symbol: "arrow.down", value: state.down, tint: .green, alignment: .leading)
                        .opacity(stale ? 0.5 : 1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedSpeed(title: "Wysyłanie", symbol: "arrow.up", value: state.up, tint: .orange, alignment: .trailing)
                        .opacity(stale ? 0.5 : 1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DetailsRow(state: state, isStale: stale)
                        .padding(.top, 4)
                }
            } compactLeading: {
                CompactSpeed(symbol: "arrow.down", value: state.down, tint: .green)
                    .opacity(stale ? 0.5 : 1)
            } compactTrailing: {
                CompactSpeed(symbol: "arrow.up", value: state.up, tint: .orange)
                    .opacity(stale ? 0.5 : 1)
            } minimal: {
                Text(formatSpeedMinimal(max(state.down, state.up)))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(stale ? Color.secondary : Color.green)
            }
            .keylineTint(Color.green)
        }
    }
}

// MARK: - Widoki

/// Kompaktowa połówka Wyspy: strzałka + liczba + mała jednostka.
private struct CompactSpeed: View {
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

private struct DetailsRow: View {
    let state: SpeedAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isStale {
                Label("Wstrzymane – otwórz aplikację", systemImage: "pause.circle.fill")
                    .foregroundStyle(Color.secondary)
            } else {
                Label(formatCPU(state.cpu), systemImage: "cpu")
                Label(thermalLabel(state.thermal), systemImage: "thermometer.medium")
                    .foregroundStyle(thermalColor(state.thermal))
                Spacer(minLength: 0)
                Text("↓ \(formatBytes(state.downTotal))  ↑ \(formatBytes(state.upTotal))")
                    .foregroundStyle(Color.secondary)
            }
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

private struct LockScreenView: View {
    let state: SpeedAttributes.ContentState
    let startedAt: Date
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ExpandedSpeed(title: "Pobieranie", symbol: "arrow.down", value: state.down, tint: .green, alignment: .leading)
                Spacer()
                ExpandedSpeed(title: "Wysyłanie", symbol: "arrow.up", value: state.up, tint: .orange, alignment: .trailing)
            }
            .opacity(isStale ? 0.5 : 1)
            DetailsRow(state: state, isStale: isStale)
            Text("Sesja od \(startedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(Color.secondary)
        }
        .foregroundStyle(Color.white)
        .padding(16)
    }
}
