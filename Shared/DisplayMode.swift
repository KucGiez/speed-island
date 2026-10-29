import Foundation

/// Co SpeedIsland pokazuje na Wyspie. Wybór użytkownika, zapisany w stanie Live Activity.
enum DisplayMode: Int, Codable, CaseIterable, Identifiable {
    case transfer
    case thermal
    case both

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .transfer: "Transfer"
        case .thermal: "Termika"
        case .both: "Oba"
        }
    }

    var next: DisplayMode {
        DisplayMode(rawValue: (rawValue + 1) % DisplayMode.allCases.count) ?? .both
    }
}

/// Co pokazać, gdy na Wyspie jest miejsce tylko na jeden element
/// (widok minimalny obok innej aplikacji albo zwężona Wyspa w iOS 27).
enum SingleSlot {
    case thermal
    case speed
}

extension SpeedAttributes.ContentState {
    /// 🔥 albo 💀: stan, o którym warto wiedzieć od razu.
    var isHot: Bool { thermal >= 2 }

    /// W trybie „Oba” pojedyncze pole zwykle pokazuje prędkość, a przy przegrzaniu ikonę termiki.
    var singleSlot: SingleSlot {
        switch mode {
        case .transfer: .speed
        case .thermal: .thermal
        case .both: isHot ? .thermal : .speed
        }
    }

    /// Przeważający kierunek ruchu (do widoków z jednym polem).
    var dominantIsDownload: Bool { down >= up }
    var dominantSpeed: Double { max(down, up) }

    /// To, co faktycznie widać w kompakcie i widoku minimalnym w danym trybie.
    /// Zmiana klucza = aktualizacja Live Activity; reszta (CPU, sumy) odświeża się z heartbeatem.
    /// Wejście na 🔥/💀 zmienia klucz w każdym trybie, żeby alarm przegrzania zadziałał zawsze.
    var islandKey: String {
        let speeds = "\(formatSpeedDisplay(down))|\(formatSpeedDisplay(up))"
        let alarm = isHot ? thermal : 0
        switch mode {
        case .transfer: return "T|\(speeds)|\(alarm)"
        case .thermal: return "C|\(thermal)"
        case .both: return "B|\(speeds)|\(thermal)"
        }
    }
}
