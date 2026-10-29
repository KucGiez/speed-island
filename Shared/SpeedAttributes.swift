import ActivityKit
import Foundation

/// Wspólne atrybuty Live Activity (kompilowane w aplikacji i w rozszerzeniu widgetu).
struct SpeedAttributes: ActivityAttributes {
    /// Jedna próbka pomiaru plus wybrany tryb. Służy też jako stan Live Activity (limit 4 KB z dużym zapasem).
    struct ContentState: Codable, Hashable {
        /// Prędkość pobierania [B/s].
        var down: Double
        /// Prędkość wysyłania [B/s].
        var up: Double
        /// Obciążenie CPU całego urządzenia 0...1; nil, gdy jeszcze nieznane.
        var cpu: Double?
        /// `ProcessInfo.ThermalState.rawValue`: 0 nominal, 1 fair, 2 serious, 3 critical.
        /// iOS nie udostępnia aplikacjom temperatury w °C, to jedyny dostępny sygnał.
        var thermal: Int
        /// Bajty pobrane od startu sesji.
        var downTotal: UInt64
        /// Bajty wysłane od startu sesji.
        var upTotal: UInt64
        /// Co pokazać na Wyspie.
        var mode: DisplayMode
        /// Kompakt tylko po lewej stronie kamery (prawa pusta). Dotyczy trybów Transfer i Oba.
        var oneSide: Bool

        static let zero = ContentState(down: 0, up: 0, cpu: nil, thermal: 0, downTotal: 0, upTotal: 0, mode: .both, oneSide: false)
    }

    /// Początek sesji (do podpisu „od 12:03”).
    var startedAt: Date
}
