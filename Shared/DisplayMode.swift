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
}
