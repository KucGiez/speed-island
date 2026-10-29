import SwiftUI

private let kibi = 1024.0
private let mebi = 1024.0 * 1024.0

/// Prędkość zaokrąglona tak, jak widać ją na Wyspie i ekranie blokady:
/// - poniżej 1 KB/s „0” (szum: powiadomienia push, keep-alive),
/// - do 100 KB/s co 1 KB, potem co 10 KB, od 1 MB/s co 0,1 MB, od 10 MB/s co 1 MB.
/// Mniej różnych wartości oznacza mniej aktualizacji Live Activity przy stałym ruchu.
/// Liczba całkowita, bez tekstu i formatowania: tanie porównanie przy każdym pomiarze.
struct SpeedBucket: Hashable, Sendable {
    /// KB/s albo dziesiąte części MB/s (gdy `megabytes`).
    let value: Int
    let megabytes: Bool

    init(_ bytesPerSecond: Double) {
        let bytes = max(0, bytesPerSecond)
        let kb = bytes / kibi
        let tensOfKB = Int((kb / 10).rounded()) * 10
        if kb < 1 {
            value = 0
            megabytes = false
        } else if kb < 100 {
            value = Int(kb.rounded())
            megabytes = false
        } else if tensOfKB < 1000 {
            value = tensOfKB
            megabytes = false
        } else {
            let tenths = Int((bytes / mebi * 10).rounded())
            // Od 10 MB/s pełne megabajty (zapis w dziesiątych, zaokrąglony do 10).
            value = tenths < 100 ? tenths : (tenths + 5) / 10 * 10
            megabytes = true
        }
    }
}

/// Liczba i jednostka do wyświetlenia, np. ("84", "KB/s"), ("1,4", "MB/s"), ("23", "MB/s").
func displaySpeed(_ bytesPerSecond: Double) -> (number: String, unit: String) {
    let bucket = SpeedBucket(bytesPerSecond)
    guard bucket.megabytes else { return ("\(bucket.value)", "KB/s") }
    if bucket.value < 100 {
        return ((Double(bucket.value) / 10).formatted(.number.precision(.fractionLength(1))), "MB/s")
    }
    return ("\(bucket.value / 10)", "MB/s")
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
