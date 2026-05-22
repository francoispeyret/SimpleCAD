import Foundation

// MARK: - ShapeType

enum ShapeType: String, CaseIterable, Codable, Identifiable {
    var id: String { rawValue }

    case rectangle = "Rectangle"
    case square    = "Carré"
    case circle    = "Cercle"
    case ellipse   = "Ellipse"
    case triangle  = "Triangle"
    case line      = "Ligne"
    case polygon   = "Polygone"

    var sfSymbol: String {
        switch self {
        case .rectangle: return "rectangle"
        case .square:    return "square"
        case .circle:    return "circle"
        case .ellipse:   return "oval"
        case .triangle:  return "triangle"
        case .line:      return "line.diagonal"
        case .polygon:   return "pentagon"
        }
    }
}

// MARK: - Tool

enum Tool: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case select      = "Sélectionner"
    case pointSelect = "Points"
    case rectangle   = "Rectangle"
    case ellipse     = "Ellipse"
    case triangle    = "Triangle"
    case line        = "Ligne"

    var shapeType: ShapeType? {
        switch self {
        case .select, .pointSelect:
            return nil
        case .rectangle: return .rectangle
        case .ellipse:   return .ellipse
        case .triangle:  return .triangle
        case .line:      return .line
        }
    }

    var sfSymbol: String {
        switch self {
        case .select:      return "arrow.up.left.circle.fill"
        case .pointSelect: return "arrow.up.left.circle.dotted"
        case .rectangle:   return "rectangle"
        case .ellipse:     return "oval"
        case .triangle:    return "triangle"
        case .line:        return "line.diagonal"
        }
    }

    var constrainedToSquare: Bool { false }
}
