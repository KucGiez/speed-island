import SwiftUI

private let kibi = 1024.0
private let mebi = 1024.0 * 1024.0

/// Pełny zapis, np. „84,2 KB/s”. Separator dziesiętny zgodny z ustawieniami regionu.
func formatSpeedFull(_ bytesPerSecond: Double) -> String {
    let b = max(0, bytesPerSecond)
    if b < kibi { return "\(Int(b.rounded())) B/s" }
    if b < mebi { return "\((b / kibi).formatted(.number.precision(.fractionLength(1)))) KB/s" }
    return "\((b / mebi).formatted(.number.precision(.fractionLength(1)))) MB/s"
}

/// Liczba i jednostka do kompaktowego widoku Wyspy, np. ("84", "KB/s"), ("1,4", "MB/s").
func speedCompactParts(_ bytesPerSecond: Double) -> (number: String, unit: String) {
    let b = max(0, bytesPerSecond)
    if b < kibi { return ("\(Int(b.rounded()))", "B/s") }
    if b < mebi { return ("\(Int((b / kibi).rounded()))", "KB/s") }
    let m = b / mebi
    let digits = m < 10 ? 1 : 0
    return (m.formatted(.number.precision(.fractionLength(digits))), "MB/s")
}

/// Najkrótszy zapis do widoku minimalnego, np. „84K”, „1,4M”.
func formatSpeedMinimal(_ bytesPerSecond: Double) -> String {
    let b = max(0, bytesPerSecond)
    if b < kibi { return "0K" }
    if b < mebi { return "\(Int((b / kibi).rounded()))K" }
    let m = b / mebi
    return "\(m.formatted(.number.precision(.fractionLength(m < 10 ? 1 : 0))))M"
}

/// Suma bajtów, np. „1,2 GB”.
func formatBytes(_ bytes: UInt64) -> String {
    Int64(clamping: bytes).formatted(.byteCount(style: .file))
}

/// Obciążenie CPU, np. „23%”, albo „–”, gdy nieznane.
func formatCPU(_ load: Double?) -> String {
    guard let load else { return "–" }
    return "\(Int((load * 100).rounded()))%"
}

/// Stan termiczny systemu (iOS nie podaje °C aplikacjom).
func thermalLabel(_ raw: Int) -> String {
    switch raw {
    case ..<1: return "OK"
    case 1: return "Ciepło"
    case 2: return "Gorąco"
    default: return "Krytycznie"
    }
}

/// Ikona poziomu termicznego: ❄️ OK, 🌴 ciepło, 🔥 gorąco, 💀 krytycznie.
func thermalIcon(_ raw: Int) -> String {
    switch raw {
    case ..<1: return "❄️"
    case 1: return "🌴"
    case 2: return "🔥"
    default: return "💀"
    }
}

func thermalColor(_ raw: Int) -> Color {
    switch raw {
    case ..<1: return .green
    case 1: return .yellow
    case 2: return .orange
    default: return .red
    }
}
