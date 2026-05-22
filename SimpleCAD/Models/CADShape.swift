import AppKit

// MARK: - DocumentUnit

enum DocumentUnit: String, CaseIterable, Codable, Identifiable {
    var id: String { rawValue }
    case mm = "mm"
    case cm = "cm"
    case m  = "m"
    case km = "km"
    case `in` = "in"
    case ft   = "ft"
    case yd   = "yd"
    case mi   = "mi"

    // Pixels per unit at 96 DPI (1 in = 96 px, 1 in = 25.4 mm)
    var pixelsPerUnit: Double {
        switch self {
        case .mm: return 96.0 / 25.4
        case .cm: return 96.0 / 2.54
        case .m:  return 96.0 / 0.0254
        case .km: return 96.0 / 0.0000254
        case .in: return 96.0
        case .ft: return 96.0 * 12.0
        case .yd: return 96.0 * 36.0
        case .mi: return 96.0 * 63360.0
        }
    }

    var decimals: Int {
        switch self {
        case .mm: return 1
        case .cm: return 2
        case .m:  return 3
        case .km: return 6
        case .in: return 2
        case .ft: return 3
        case .yd: return 3
        case .mi: return 5
        }
    }

    func fromPixels(_ px: Double) -> Double { px / pixelsPerUnit }
    func toPixels(_ value: Double) -> Double { value * pixelsPerUnit }

    /// "25.4 mm"
    func format(_ px: Double) -> String {
        String(format: "%.\(decimals)f \(rawValue)", fromPixels(px))
    }

    /// "25.4" (sans label d'unité, pour les champs de saisie)
    func formatValue(_ px: Double) -> String {
        String(format: "%.\(decimals)f", fromPixels(px))
    }
}

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

// MARK: - ShapeType

enum ShapeType: String, CaseIterable, Codable, Identifiable {
    var id: String { rawValue }
    case rectangle = "Rectangle"
    case square    = "Carré"
    case circle    = "Cercle"
    case ellipse   = "Ellipse"
    case triangle  = "Triangle"
    case line      = "Ligne"

    var sfSymbol: String {
        switch self {
        case .rectangle: return "rectangle"
        case .square:    return "square"
        case .circle:    return "circle"
        case .ellipse:   return "oval"
        case .triangle:  return "triangle"
        case .line:      return "line.diagonal"
        }
    }
}

// MARK: - Tool

enum Tool: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case select    = "Sélectionner"
    case rectangle = "Rectangle"
    case square    = "Carré"
    case circle    = "Cercle"
    case ellipse   = "Ellipse"
    case triangle  = "Triangle"
    case line      = "Ligne"

    var shapeType: ShapeType? {
        switch self {
        case .select:    return nil
        case .rectangle: return .rectangle
        case .square:    return .square
        case .circle:    return .circle
        case .ellipse:   return .ellipse
        case .triangle:  return .triangle
        case .line:      return .line
        }
    }

    var sfSymbol: String {
        switch self {
        case .select:    return "cursorarrow"
        case .rectangle: return "rectangle"
        case .square:    return "square"
        case .circle:    return "circle"
        case .ellipse:   return "oval"
        case .triangle:  return "triangle"
        case .line:      return "line.diagonal"
        }
    }

    var constrainedToSquare: Bool { self == .square || self == .circle }
}

// MARK: - CodableRect (CGRect wrapper)

struct CodableRect: Codable, Equatable {
    var x, y, width, height: Double

    init(_ r: CGRect) {
        x = Double(r.origin.x); y = Double(r.origin.y)
        width = Double(r.size.width); height = Double(r.size.height)
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

// MARK: - CADShape

struct CADShape: Identifiable, Codable {
    var id:          UUID
    var name:        String
    var type:        ShapeType
    var codableBounds: CodableRect
    var fillColor:   CADColor
    var strokeColor: CADColor
    var strokeWidth: Double
    var rotationAngle: Double

    var bounds: CGRect {
        get { codableBounds.cgRect }
        set { codableBounds = CodableRect(newValue) }
    }

    var center: CGPoint {
        CGPoint(x: bounds.midX, y: bounds.midY)
    }

    var visualBounds: CGRect {
        let points = rotatedBoundsPoints()
        guard !points.isEmpty else { return bounds.standardized }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!,
                      width: xs.max()! - xs.min()!,
                      height: ys.max()! - ys.min()!)
    }

    var rotatedHandlePoints: [CGPoint] {
        rotatedBoundsPoints()
    }

    // 96 DPI → 1 inch = 25.4 mm → 96/25.4 px/mm
    static let pixelsPerMM: Double = 96.0 / 25.4

    var widthMM:  Double { Double(bounds.width)  / Self.pixelsPerMM }
    var heightMM: Double { Double(bounds.height) / Self.pixelsPerMM }
    var xMM:      Double { Double(bounds.origin.x) / Self.pixelsPerMM }
    var yMM:      Double { Double(bounds.origin.y) / Self.pixelsPerMM }

    init(id: UUID = UUID(), type: ShapeType, bounds: CGRect, name: String,
         fillColor: CADColor = .white, strokeColor: CADColor = .black,
         strokeWidth: Double = 2.0, rotationAngle: Double = 0.0) {
        self.id = id; self.type = type; self.codableBounds = CodableRect(bounds)
        self.name = name; self.fillColor = fillColor
        self.strokeColor = strokeColor; self.strokeWidth = strokeWidth
        self.rotationAngle = Self.normalizedRotation(rotationAngle)
    }

    func bezierPath() -> NSBezierPath {
        let path = baseBezierPath()
        guard abs(rotationAngle) > 0.0001 else { return path }

        var transform = AffineTransform(translationByX: center.x, byY: center.y)
        transform.rotate(byDegrees: CGFloat(rotationAngle))
        transform.translate(x: -center.x, y: -center.y)
        path.transform(using: transform)
        return path
    }

    private func baseBezierPath() -> NSBezierPath {
        switch type {
        case .rectangle, .square:
            return NSBezierPath(rect: bounds.standardized)
        case .circle, .ellipse:
            return NSBezierPath(ovalIn: bounds.standardized)
        case .triangle:
            let b = bounds.standardized
            let p = NSBezierPath()
            p.move(to: CGPoint(x: b.midX, y: b.minY))
            p.line(to: CGPoint(x: b.maxX, y: b.maxY))
            p.line(to: CGPoint(x: b.minX, y: b.maxY))
            p.close()
            return p
        case .line:
            let b = bounds.standardized
            let p = NSBezierPath()
            p.move(to: CGPoint(x: b.minX, y: b.midY))
            p.line(to: CGPoint(x: b.maxX, y: b.midY))
            return p
        }
    }

    func contains(_ point: CGPoint) -> Bool {
        let localPoint = rotatedPoint(point, byDegrees: -rotationAngle, around: center)
        let b = bounds.standardized

        switch type {
        case .rectangle, .square:
            return b.contains(localPoint)
        case .circle, .ellipse:
            let cx = b.midX, cy = b.midY
            let rx = b.width / 2, ry = b.height / 2
            guard rx > 0, ry > 0 else { return false }
            let dx = (localPoint.x - cx) / rx
            let dy = (localPoint.y - cy) / ry
            return dx * dx + dy * dy <= 1.0
        case .triangle:
            return baseBezierPath().contains(localPoint)
        case .line:
            let tol = max(CGFloat(strokeWidth) + 4, 8)
            return b.minX <= localPoint.x && localPoint.x <= b.maxX
                && abs(localPoint.y - b.midY) <= tol
        }
    }

    static func normalizedRotation(_ angle: Double) -> Double {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized <= -180 { normalized += 360 }
        if normalized > 180 { normalized -= 360 }
        return abs(normalized) < 0.0001 ? 0 : normalized
    }

    private func rotatedBoundsPoints() -> [CGPoint] {
        let b = bounds.standardized
        let points = [
            CGPoint(x: b.minX, y: b.minY),
            CGPoint(x: b.maxX, y: b.minY),
            CGPoint(x: b.maxX, y: b.maxY),
            CGPoint(x: b.minX, y: b.maxY),
        ]
        guard abs(rotationAngle) > 0.0001 else { return points }
        return points.map { rotatedPoint($0, byDegrees: rotationAngle, around: center) }
    }

    private func rotatedPoint(_ point: CGPoint, byDegrees degrees: Double, around center: CGPoint) -> CGPoint {
        let radians = degrees * Double.pi / 180
        let dx = point.x - center.x
        let dy = point.y - center.y
        let cosA = CGFloat(cos(radians))
        let sinA = CGFloat(sin(radians))
        return CGPoint(x: center.x + dx * cosA - dy * sinA,
                       y: center.y + dx * sinA + dy * cosA)
    }
}
