import SwiftUI

private let kibi = 1024.0
private let mebi = 1024.0 * 1024.0

/// Prędkość tak, jak widać ją na Wyspie i ekranie blokady:
/// - poniżej 1 KB/s „0” (szum: powiadomienia push, keep-alive),
/// - do 100 KB/s co 1 KB, potem co 10 KB, od 1 MB/s z jednym miejscem po przecinku, od 10 MB/s bez.
/// Mniej różnych wartości oznacza mniej aktualizacji Live Activity przy stałym ruchu.
func displaySpeed(_ bytesPerSecond: Double) -> (number: String, unit: String) {
    let kb = max(0, bytesPerSecond) / kibi
    if kb < 1 { return ("0", "KB/s") }
    if kb < 100 { return ("\(Int(kb.rounded()))", "KB/s") }
    let tens = Int((kb / 10).rounded()) * 10
    if tens < 1000 { return ("\(tens)", "KB/s") }
    let mb = max(0, bytesPerSecond) / mebi
    return (mb.formatted(.number.precision(.fractionLength(mb < 10 ? 1 : 0))), "MB/s")
}

/// „84 KB/s” w tym samym zaokrągleniu co Wyspa.
func formatSpeedDisplay(_ bytesPerSecond: Double) -> String {
    let p = displaySpeed(bytesPerSecond)
    return "\(p.number) \(p.unit)"
}

/// Najkrótszy zapis, np. „84K”, „1,4M”.
func formatSpeedMinimal(_ bytesPerSecond: Double) -> String {
    let p = displaySpeed(bytesPerSecond)
    return p.number + (p.unit == "MB/s" ? "M" : "K")
}

/// Pełna precyzja do aplikacji na pierwszym planie, np. „84,2 KB/s”.
func formatSpeedFull(_ bytesPerSecond: Double) -> String {
    let b = max(0, bytesPerSecond)
    if b < kibi { return "\(Int(b.rounded())) B/s" }
    if b < mebi { return "\((b / kibi).formatted(.number.precision(.fractionLength(1)))) KB/s" }
    return "\((b / mebi).formatted(.number.precision(.fractionLength(1)))) MB/s"
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
