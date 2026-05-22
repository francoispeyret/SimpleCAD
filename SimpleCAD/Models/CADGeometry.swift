import AppKit

// MARK: - Codable geometry wrappers

struct CodableRect: Codable, Equatable {
    var x, y, width, height: Double

    init(_ rect: CGRect) {
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.size.width)
        height = Double(rect.size.height)
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct CodablePoint: Codable, Equatable {
    var x, y: Double

    init(_ point: CGPoint) {
        x = Double(point.x)
        y = Double(point.y)
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

// MARK: - CADGeometry

enum CADGeometry {
    static func normalizedRotation(_ angle: Double) -> Double {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized <= -180 { normalized += 360 }
        if normalized > 180 { normalized -= 360 }
        return abs(normalized) < 0.0001 ? 0 : normalized
    }

    static func rotate(_ point: CGPoint, byDegrees degrees: Double, around center: CGPoint) -> CGPoint {
        let radians = degrees * Double.pi / 180
        let dx = point.x - center.x
        let dy = point.y - center.y
        let cosA = CGFloat(cos(radians))
        let sinA = CGFloat(sin(radians))
        return CGPoint(x: center.x + dx * cosA - dy * sinA,
                       y: center.y + dx * sinA + dy * cosA)
    }

    static func rotatedUnitX(byDegrees degrees: Double) -> CGVector {
        let radians = degrees * Double.pi / 180
        return CGVector(dx: CGFloat(cos(radians)), dy: CGFloat(sin(radians)))
    }

    static func rotatedUnitY(byDegrees degrees: Double) -> CGVector {
        let radians = degrees * Double.pi / 180
        return CGVector(dx: CGFloat(-sin(radians)), dy: CGFloat(cos(radians)))
    }

    static func offset(_ point: CGPoint, along vector: CGVector, by distance: CGFloat) -> CGPoint {
        CGPoint(x: point.x + vector.dx * distance,
                y: point.y + vector.dy * distance)
    }

    static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    static func reversed(_ vector: CGVector) -> CGVector {
        CGVector(dx: -vector.dx, dy: -vector.dy)
    }

    static func dot(_ a: CGVector, _ b: CGVector) -> CGFloat {
        a.dx * b.dx + a.dy * b.dy
    }

    static func readableLabelAngle(_ angle: Double) -> Double {
        var normalized = normalizedRotation(angle)
        if normalized > 90 { normalized -= 180 }
        if normalized < -90 { normalized += 180 }
        return normalized
    }

    static func angleDegrees(from center: CGPoint, to point: CGPoint) -> Double {
        atan2(Double(point.y - center.y), Double(point.x - center.x)) * 180 / Double.pi
    }

    static func constrainedLineEnd(from start: CGPoint,
                                   to point: CGPoint,
                                   snapTo45Degrees: Bool) -> CGPoint {
        guard snapTo45Degrees else { return point }

        let dx = point.x - start.x
        let dy = point.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return point }

        let step = Double.pi / 4
        let angle = atan2(Double(dy), Double(dx))
        let snappedAngle = (angle / step).rounded() * step
        return CGPoint(x: start.x + CGFloat(cos(snappedAngle)) * length,
                       y: start.y + CGFloat(sin(snappedAngle)) * length)
    }

    static func rotatedRectBounds(center: CGPoint, size: CGSize, angleDegrees: Double) -> CGRect {
        let halfW = size.width / 2
        let halfH = size.height / 2
        let corners = [
            CGPoint(x: center.x - halfW, y: center.y - halfH),
            CGPoint(x: center.x + halfW, y: center.y - halfH),
            CGPoint(x: center.x + halfW, y: center.y + halfH),
            CGPoint(x: center.x - halfW, y: center.y + halfH)
        ].map { rotate($0, byDegrees: angleDegrees, around: center) }
        return boundingRect(for: corners) ?? .zero
    }

    static func boundingRect(for points: [CGPoint]) -> CGRect? {
        guard !points.isEmpty else { return nil }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        return CGRect(x: xs.min()!,
                      y: ys.min()!,
                      width: xs.max()! - xs.min()!,
                      height: ys.max()! - ys.min()!)
    }
}
