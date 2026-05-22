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
    case select    = "Sélectionner"
    case pointSelect = "Points"
    case rectangle = "Rectangle"
    case ellipse   = "Ellipse"
    case triangle  = "Triangle"
    case line      = "Ligne"

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
        case .select:    return "arrow.up.left.circle.fill"
        case .pointSelect: return "arrow.up.left.circle.dotted"
        case .rectangle: return "rectangle"
        case .ellipse:   return "oval"
        case .triangle:  return "triangle"
        case .line:      return "line.diagonal"
        }
    }

    var constrainedToSquare: Bool { false }
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

struct CodablePoint: Codable, Equatable {
    var x, y: Double

    init(_ p: CGPoint) {
        x = Double(p.x)
        y = Double(p.y)
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

// MARK: - CADShape

struct CADShape: Identifiable, Codable, Equatable {
    var id:          UUID
    var name:        String
    var type:        ShapeType
    var codableBounds: CodableRect
    var codablePoints: [CodablePoint]?
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

    var customPoints: [CGPoint] {
        get { codablePoints?.map(\.cgPoint) ?? [] }
        set { codablePoints = newValue.isEmpty ? nil : newValue.map(CodablePoint.init) }
    }

    var visualBounds: CGRect {
        let points = visualGeometryPoints()
        guard !points.isEmpty else { return bounds.standardized }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!,
                      width: xs.max()! - xs.min()!,
                      height: ys.max()! - ys.min()!)
    }

    var rotatedHandlePoints: [CGPoint] {
        if let endpoints = lineEndpoints {
            return [endpoints.start, endpoints.end]
        }
        if type == .polygon, !customPoints.isEmpty {
            return transformedCustomPoints()
        }
        return rotatedBoundsPoints()
    }

    var lineEndpoints: (start: CGPoint, end: CGPoint)? {
        guard type == .line else { return nil }
        let b = bounds.standardized
        return (
            rotatedPoint(CGPoint(x: b.minX, y: b.midY), byDegrees: rotationAngle, around: center),
            rotatedPoint(CGPoint(x: b.maxX, y: b.midY), byDegrees: rotationAngle, around: center)
        )
    }

    // 96 DPI → 1 inch = 25.4 mm → 96/25.4 px/mm
    static let pixelsPerMM: Double = 96.0 / 25.4
    private static let minimumLineBoundsThickness: CGFloat = 8

    var widthMM:  Double { Double(bounds.width)  / Self.pixelsPerMM }
    var heightMM: Double { Double(bounds.height) / Self.pixelsPerMM }
    var xMM:      Double { Double(bounds.origin.x) / Self.pixelsPerMM }
    var yMM:      Double { Double(bounds.origin.y) / Self.pixelsPerMM }

    init(id: UUID = UUID(), type: ShapeType, bounds: CGRect, name: String,
         fillColor: CADColor = .white, strokeColor: CADColor = .black,
         strokeWidth: Double = 2.0, rotationAngle: Double = 0.0,
         points: [CGPoint] = []) {
        self.id = id; self.type = type; self.codableBounds = CodableRect(bounds)
        self.codablePoints = points.isEmpty ? nil : points.map(CodablePoint.init)
        self.name = name; self.fillColor = fillColor
        self.strokeColor = strokeColor; self.strokeWidth = strokeWidth
        self.rotationAngle = Self.normalizedRotation(rotationAngle)
    }

    static func line(from start: CGPoint,
                     to end: CGPoint,
                     name: String,
                     fillColor: CADColor = .white,
                     strokeColor: CADColor = .black,
                     strokeWidth: Double = 2.0,
                     id: UUID = UUID()) -> CADShape {
        let geometry = lineGeometry(from: start, to: end, strokeWidth: strokeWidth)
        return CADShape(id: id,
                        type: .line,
                        bounds: geometry.bounds,
                        name: name,
                        fillColor: fillColor,
                        strokeColor: strokeColor,
                        strokeWidth: strokeWidth,
                        rotationAngle: geometry.rotationAngle)
    }

    static func lineGeometry(from start: CGPoint,
                             to end: CGPoint,
                             strokeWidth: Double) -> (bounds: CGRect, rotationAngle: Double, length: CGFloat) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        let thickness = max(CGFloat(strokeWidth), minimumLineBoundsThickness)
        let center = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let bounds = CGRect(x: center.x - length / 2,
                            y: center.y - thickness / 2,
                            width: length,
                            height: thickness)
        let angle = atan2(Double(dy), Double(dx)) * 180 / Double.pi
        return (bounds, normalizedRotation(angle), length)
    }

    mutating func translate(by delta: CGSize) {
        bounds = bounds.offsetBy(dx: delta.width, dy: delta.height)
        if !customPoints.isEmpty {
            customPoints = customPoints.map {
                CGPoint(x: $0.x + delta.width, y: $0.y + delta.height)
            }
        }
    }

    mutating func resize(to newBounds: CGRect) {
        let old = bounds.standardized
        bounds = newBounds
        guard !customPoints.isEmpty else { return }

        let target = newBounds.standardized
        customPoints = customPoints.map { point in
            let xRatio = old.width == 0 ? 0.5 : (point.x - old.minX) / old.width
            let yRatio = old.height == 0 ? 0.5 : (point.y - old.minY) / old.height
            return CGPoint(x: target.minX + xRatio * target.width,
                           y: target.minY + yRatio * target.height)
        }
    }

    func editablePoints() -> [CGPoint] {
        let b = bounds.standardized

        switch type {
        case .line:
            guard let endpoints = lineEndpoints else { return [] }
            return [endpoints.start, endpoints.end]
        case .rectangle, .square:
            return [
                CGPoint(x: b.minX, y: b.minY),
                CGPoint(x: b.maxX, y: b.minY),
                CGPoint(x: b.maxX, y: b.maxY),
                CGPoint(x: b.minX, y: b.maxY)
            ].map { rotatedPoint($0, byDegrees: rotationAngle, around: center) }
        case .triangle:
            return [
                CGPoint(x: b.midX, y: b.minY),
                CGPoint(x: b.maxX, y: b.maxY),
                CGPoint(x: b.minX, y: b.maxY)
            ].map { rotatedPoint($0, byDegrees: rotationAngle, around: center) }
        case .polygon:
            return transformedCustomPoints()
        case .circle, .ellipse:
            return []
        }
    }

    func movingEditablePoint(at index: Int, to point: CGPoint) -> CADShape? {
        var points = editablePoints()
        guard points.indices.contains(index) else { return nil }
        points[index] = point

        if type == .line, points.count == 2 {
            return CADShape.line(from: points[0],
                                 to: points[1],
                                 name: name,
                                 fillColor: fillColor,
                                 strokeColor: strokeColor,
                                 strokeWidth: strokeWidth,
                                 id: id)
        }

        guard let polygonBounds = Self.bounds(for: points) else { return nil }
        return CADShape(id: id,
                        type: .polygon,
                        bounds: polygonBounds,
                        name: name,
                        fillColor: fillColor,
                        strokeColor: strokeColor,
                        strokeWidth: strokeWidth,
                        rotationAngle: 0,
                        points: points)
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
        case .polygon:
            let points = customPoints
            guard let first = points.first else {
                return NSBezierPath(rect: bounds.standardized)
            }
            let p = NSBezierPath()
            p.move(to: first)
            for point in points.dropFirst() {
                p.line(to: point)
            }
            p.close()
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
        case .polygon:
            return baseBezierPath().contains(localPoint)
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

    private func visualGeometryPoints() -> [CGPoint] {
        if type == .polygon, !customPoints.isEmpty {
            return transformedCustomPoints()
        }
        return rotatedBoundsPoints()
    }

    private func transformedCustomPoints() -> [CGPoint] {
        let points = customPoints
        guard abs(rotationAngle) > 0.0001 else { return points }
        return points.map { rotatedPoint($0, byDegrees: rotationAngle, around: center) }
    }

    private static func bounds(for points: [CGPoint]) -> CGRect? {
        guard !points.isEmpty else { return nil }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        return CGRect(x: xs.min()!,
                      y: ys.min()!,
                      width: xs.max()! - xs.min()!,
                      height: ys.max()! - ys.min()!)
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
