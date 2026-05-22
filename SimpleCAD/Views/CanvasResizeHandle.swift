import AppKit

// MARK: - ResizeHandle

enum ResizeHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    var opposite: ResizeHandle {
        switch self {
        case .topLeft:     return .bottomRight
        case .top:         return .bottom
        case .topRight:    return .bottomLeft
        case .right:       return .left
        case .bottomRight: return .topLeft
        case .bottom:      return .top
        case .bottomLeft:  return .topRight
        case .left:        return .right
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.minY)
        case .top:         return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.minY)
        case .right:       return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom:      return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.maxY)
        case .left:        return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    var affectsX: Bool {
        switch self {
        case .topLeft, .topRight, .right, .bottomRight, .bottomLeft, .left:
            return true
        case .top, .bottom:
            return false
        }
    }

    var affectsY: Bool {
        switch self {
        case .topLeft, .top, .topRight, .bottomRight, .bottom, .bottomLeft:
            return true
        case .right, .left:
            return false
        }
    }

    var cursorAngleOffset: Double {
        switch self {
        case .left, .right:
            return 0
        case .top, .bottom:
            return 90
        case .topLeft, .bottomRight:
            return -45
        case .topRight, .bottomLeft:
            return 45
        }
    }
}
