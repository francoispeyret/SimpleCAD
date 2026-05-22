import AppKit

// MARK: - DimensionDisplayMode

enum DimensionDisplayMode: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case none
    case selected
    case all

    var title: String {
        switch self {
        case .none:     return "Aucune côte"
        case .selected: return "Côte sur l'élément sélectionné"
        case .all:      return "Côte sur tous les éléments"
        }
    }

    var shortTitle: String {
        switch self {
        case .none:     return "Aucune"
        case .selected: return "Sélection"
        case .all:      return "Toutes"
        }
    }

    var sfSymbol: String {
        switch self {
        case .none:     return "cross"
        case .selected: return "rectangle.dashed"
        case .all:      return "rectangle.dashed"
        }
    }
}

// MARK: - GridDisplayMode

enum GridDisplayMode: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case none
    case standard
    case wide

    var title: String {
        switch self {
        case .none:     return "Aucune grille"
        case .standard: return "Grille par défaut"
        case .wide:     return "Grille large"
        }
    }

    var shortTitle: String {
        switch self {
        case .none:     return "Aucune"
        case .standard: return "Défaut"
        case .wide:     return "Large"
        }
    }

    var sfSymbol: String {
        switch self {
        case .none:     return "grid"
        case .standard: return "grid"
        case .wide:     return "square.grid.2x2"
        }
    }

    var spacing: CGFloat {
        switch self {
        case .none:     return 0
        case .standard: return 20
        case .wide:     return 80
        }
    }
}
