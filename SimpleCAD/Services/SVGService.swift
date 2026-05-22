import Foundation
import AppKit

// MARK: - SVG namespace constants

private let ns = "simplecad"
private let nsURI = "http://simplecad.app/ns/1.0"

// MARK: - SVGLoadResult

struct SVGLoadResult {
    var shapes:     [CADShape]
    var counters:   [ShapeType: Int]
    var canvasSize: CGSize
    var virtualCanvasSize: CGSize?
    var unit:       DocumentUnit = .mm
}

// MARK: - SVGService

enum SVGService {

    // MARK: Save

    static func save(document: CADDocument, to url: URL) throws {
        let svg = buildSVG(document: document)
        try svg.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func buildSVG(document: CADDocument) -> String {
        let exportBounds = exportBounds(for: document.shapes)
        let exportOrigin = exportBounds?.origin ?? .zero
        let w = max(exportBounds?.width ?? document.canvasSize.width, 1)
        let h = max(exportBounds?.height ?? document.canvasSize.height, 1)
        let pxMM = CADShape.pixelsPerMM

        var lines: [String] = []
        lines.append("""
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg"
     xmlns:\(ns)="\(nsURI)"
     width="\(fmt(w / pxMM))mm" height="\(fmt(h / pxMM))mm"
     viewBox="0 0 \(fmt(w)) \(fmt(h))"
     \(ns):canvas-width-mm="\(fmt(w / pxMM))"
     \(ns):canvas-height-mm="\(fmt(h / pxMM))"
     \(ns):virtual-canvas-width-mm="\(fmt(document.canvasSize.width / pxMM))"
     \(ns):virtual-canvas-height-mm="\(fmt(document.canvasSize.height / pxMM))"
     \(ns):unit="\(document.unit.rawValue)">
""")

        lines.append("  <title>SimpleCAD Plan</title>")

        for shape in document.shapes {
            lines.append(shapeToSVG(shape, offset: CGSize(width: -exportOrigin.x, height: -exportOrigin.y)))
        }

        lines.append("</svg>")
        return lines.joined(separator: "\n")
    }

    private static func shapeToSVG(_ originalShape: CADShape, offset: CGSize = .zero) -> String {
        var shape = originalShape
        shape.translate(by: offset)
        let b = shape.bounds
        let fill   = svgColor(shape.fillColor)
        let fillOp = fmt(shape.fillColor.alpha)
        let stroke = svgColor(shape.strokeColor)
        let strokeOp = fmt(shape.strokeColor.alpha)
        let sw = fmt(shape.strokeWidth)
        let rotation = CADShape.normalizedRotation(shape.rotationAngle)
        let rotationAttrs = abs(rotation) > 0.0001
            ? """
      transform="rotate(\(fmt(rotation)) \(fmt(b.midX)) \(fmt(b.midY))"
      \(ns):rotation-deg="\(fmt(rotation))"
"""
            : """
      \(ns):rotation-deg="0"
"""

        let commonAttrs = """
      fill="\(fill)" fill-opacity="\(fillOp)"
      stroke="\(stroke)" stroke-opacity="\(strokeOp)" stroke-width="\(sw)"
\(rotationAttrs)
      \(ns):id="\(shape.id.uuidString)"
      \(ns):name="\(xmlEscape(shape.name))"
      \(ns):type="\(shape.type.rawValue)"
      \(ns):x-mm="\(fmt(shape.xMM))" \(ns):y-mm="\(fmt(shape.yMM))"
      \(ns):width-mm="\(fmt(shape.widthMM))" \(ns):height-mm="\(fmt(shape.heightMM))"
      \(ns):stroke-width-mm="\(fmt(shape.strokeWidth / CADShape.pixelsPerMM))"
"""

        switch shape.type {
        case .rectangle, .square:
            return """
  <rect x="\(fmt(b.minX))" y="\(fmt(b.minY))"
        width="\(fmt(b.width))" height="\(fmt(b.height))"
\(commonAttrs)/>
"""
        case .circle:
            let cx = b.midX, cy = b.midY
            if abs(b.width - b.height) <= 0.0001 {
                let r = b.width / 2
                return """
  <circle cx="\(fmt(cx))" cy="\(fmt(cy))" r="\(fmt(r))"
\(commonAttrs)/>
"""
            }
            let rx = b.width / 2, ry = b.height / 2
            return """
  <ellipse cx="\(fmt(cx))" cy="\(fmt(cy))" rx="\(fmt(rx))" ry="\(fmt(ry))"
\(commonAttrs)/>
"""
        case .ellipse:
            let cx = b.midX, cy = b.midY, rx = b.width / 2, ry = b.height / 2
            return """
  <ellipse cx="\(fmt(cx))" cy="\(fmt(cy))" rx="\(fmt(rx))" ry="\(fmt(ry))"
\(commonAttrs)/>
"""
        case .triangle:
            let pts = "\(fmt(b.midX)),\(fmt(b.minY)) \(fmt(b.maxX)),\(fmt(b.maxY)) \(fmt(b.minX)),\(fmt(b.maxY))"
            return """
  <polygon points="\(pts)"
\(commonAttrs)/>
"""
        case .polygon:
            let points = shape.customPoints
            let pts = points
                .map { "\(fmt($0.x)),\(fmt($0.y))" }
                .joined(separator: " ")
            return """
  <polygon points="\(pts)"
\(commonAttrs)/>
"""
        case .line:
            return """
  <line x1="\(fmt(b.minX))" y1="\(fmt(b.midY))" x2="\(fmt(b.maxX))" y2="\(fmt(b.midY))"
\(commonAttrs)/>
"""
        }
    }

    private static func exportBounds(for shapes: [CADShape]) -> CGRect? {
        guard var bounds = shapes.first.map(exportBounds(for:)) else { return nil }
        for shape in shapes.dropFirst() {
            bounds = bounds.union(exportBounds(for: shape))
        }
        return bounds.standardized
    }

    private static func exportBounds(for shape: CADShape) -> CGRect {
        let strokeOverflow = shape.strokeColor.alpha > 0 ? max(CGFloat(shape.strokeWidth) / 2, 0) : 0
        return shape.visualBounds.standardized.insetBy(dx: -strokeOverflow, dy: -strokeOverflow)
    }

    // MARK: Load

    static func load(from url: URL) throws -> SVGLoadResult {
        let data = try Data(contentsOf: url)
        let parser = SVGParser()
        return try parser.parse(data: data)
    }

    // MARK: Helpers

    private static func svgColor(_ c: CADColor) -> String {
        c.alpha == 0 ? "none" : c.hexString
    }

    private static func fmt(_ v: Double) -> String {
        let s = String(format: "%.4f", v)
        // trim trailing zeros
        var result = s
        if result.contains(".") {
            while result.hasSuffix("0") { result.removeLast() }
            if result.hasSuffix(".") { result.removeLast() }
        }
        return result
    }

    private static func fmt(_ v: CGFloat) -> String { fmt(Double(v)) }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&",  with: "&amp;")
         .replacingOccurrences(of: "<",  with: "&lt;")
         .replacingOccurrences(of: ">",  with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - SVGParser

private class SVGParser: NSObject, XMLParserDelegate {
    var shapes:    [CADShape]      = []
    var counters:  [ShapeType: Int] = [:]
    var canvasSize = CGSize(width: 2480, height: 1754)
    var virtualCanvasSize: CGSize?
    var unit:      DocumentUnit    = .mm
    var error: Error?

    func parse(data: Data) throws -> SVGLoadResult {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        if let e = error { throw e }
        return SVGLoadResult(shapes: shapes,
                             counters: counters,
                             canvasSize: canvasSize,
                             virtualCanvasSize: virtualCanvasSize,
                             unit: unit)
    }

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attrs: [String: String]) {

        // Read canvas size and unit from svg root
        if element == "svg" {
            if let wmm = attrs["\(ns):canvas-width-mm"].flatMap(Double.init),
               let hmm = attrs["\(ns):canvas-height-mm"].flatMap(Double.init) {
                canvasSize = CGSize(width: wmm * CADShape.pixelsPerMM,
                                   height: hmm * CADShape.pixelsPerMM)
            }
            if let wmm = attrs["\(ns):virtual-canvas-width-mm"].flatMap(Double.init),
               let hmm = attrs["\(ns):virtual-canvas-height-mm"].flatMap(Double.init) {
                virtualCanvasSize = CGSize(width: wmm * CADShape.pixelsPerMM,
                                           height: hmm * CADShape.pixelsPerMM)
            }
            if let unitStr = attrs["\(ns):unit"],
               let u = DocumentUnit(rawValue: unitStr) {
                unit = u
            }
            return
        }

        guard let typeStr = attrs["\(ns):type"],
              let type = ShapeType.allCases.first(where: { $0.rawValue == typeStr })
        else { return }

        let idStr  = attrs["\(ns):id"] ?? UUID().uuidString
        let id     = UUID(uuidString: idStr) ?? UUID()
        let name   = attrs["\(ns):name"] ?? type.rawValue

        let fill   = parseColor(hex: attrs["fill"],   opacity: attrs["fill-opacity"])
        let stroke = parseColor(hex: attrs["stroke"], opacity: attrs["stroke-opacity"])
        let sw     = Double(attrs["stroke-width"] ?? "2") ?? 2.0

        if element == "line", type == .line {
            let x1 = CGFloat(Double(attrs["x1"] ?? "0") ?? 0)
            let y1 = CGFloat(Double(attrs["y1"] ?? "0") ?? 0)
            let x2 = CGFloat(Double(attrs["x2"] ?? "0") ?? 0)
            let y2 = CGFloat(Double(attrs["y2"] ?? "0") ?? 0)
            var start = CGPoint(x: x1, y: y1)
            var end = CGPoint(x: x2, y: y2)

            if let rotation = parseRotateTransform(attrs: attrs) {
                let center = rotation.center ?? .zero
                start = rotatePoint(start, byDegrees: rotation.angle, around: center)
                end = rotatePoint(end, byDegrees: rotation.angle, around: center)
            }

            let shape = CADShape.line(from: start,
                                      to: end,
                                      name: name,
                                      fillColor: fill,
                                      strokeColor: stroke,
                                      strokeWidth: sw,
                                      id: id)
            shapes.append(shape)

            let num = Int(name.split(separator: " ").last ?? "1") ?? 1
            counters[type] = max(counters[type] ?? 0, num)
            return
        }

        // Reconstruct bounds from pixel coordinates in the SVG element
        let bounds: CGRect
        switch element {
        case "rect":
            let x = CGFloat(Double(attrs["x"] ?? "0") ?? 0)
            let y = CGFloat(Double(attrs["y"] ?? "0") ?? 0)
            let w = CGFloat(Double(attrs["width"] ?? "0") ?? 0)
            let h = CGFloat(Double(attrs["height"] ?? "0") ?? 0)
            bounds = CGRect(x: x, y: y, width: w, height: h)
        case "circle":
            let cx = CGFloat(Double(attrs["cx"] ?? "0") ?? 0)
            let cy = CGFloat(Double(attrs["cy"] ?? "0") ?? 0)
            let r  = CGFloat(Double(attrs["r"]  ?? "0") ?? 0)
            bounds = CGRect(x: cx - r, y: cy - r, width: r*2, height: r*2)
        case "ellipse":
            let cx = CGFloat(Double(attrs["cx"] ?? "0") ?? 0)
            let cy = CGFloat(Double(attrs["cy"] ?? "0") ?? 0)
            let rx = CGFloat(Double(attrs["rx"] ?? "0") ?? 0)
            let ry = CGFloat(Double(attrs["ry"] ?? "0") ?? 0)
            bounds = CGRect(x: cx - rx, y: cy - ry, width: rx*2, height: ry*2)
        case "polygon":
            // Parse points to get bounding box
            let points = polygonPoints(from: attrs["points"] ?? "")
            bounds = polygonBounds(from: points)
            if type == .polygon {
                let rotation = parseRotation(attrs: attrs)
                let shape = CADShape(id: id, type: type, bounds: bounds, name: name,
                                     fillColor: fill, strokeColor: stroke,
                                     strokeWidth: sw, rotationAngle: rotation,
                                     points: points)
                shapes.append(shape)

                let num = Int(name.split(separator: " ").last ?? "1") ?? 1
                counters[type] = max(counters[type] ?? 0, num)
                return
            }
        case "line":
            return
        default:
            return
        }

        let rotation = parseRotation(attrs: attrs)
        let shape = CADShape(id: id, type: type, bounds: bounds, name: name,
                             fillColor: fill, strokeColor: stroke,
                             strokeWidth: sw, rotationAngle: rotation)
        shapes.append(shape)

        let num = Int(name.split(separator: " ").last ?? "1") ?? 1
        counters[type] = max(counters[type] ?? 0, num)
    }

    func parser(_ parser: XMLParser, parseErrorOccurred error: Error) {
        self.error = error
    }

    private func parseColor(hex: String?, opacity: String?) -> CADColor {
        guard let hex, hex.lowercased() != "none" else {
            return CADColor.clear
        }
        let alpha = Double(opacity ?? "1") ?? 1.0
        return CADColor(hex: hex, alpha: alpha)
    }

    private func parseRotation(attrs: [String: String]) -> Double {
        if let raw = attrs["\(ns):rotation-deg"] ?? attrs["\(ns):rotation"],
           let rotation = Double(raw) {
            return rotation
        }
        return parseRotateTransform(attrs: attrs)?.angle ?? 0
    }

    private func parseRotateTransform(attrs: [String: String]) -> (angle: Double, center: CGPoint?)? {
        guard let transform = attrs["transform"],
              let open = transform.range(of: "rotate(") else { return nil }

        let afterOpen = transform[open.upperBound...]
        guard let close = afterOpen.firstIndex(of: ")") else { return nil }
        let content = afterOpen[..<close]
        let values = content
            .split { $0 == " " || $0 == "," || $0 == "\t" || $0 == "\n" }
            .compactMap { Double($0) }
        guard let angle = values.first else { return nil }

        let center: CGPoint?
        if values.count >= 3 {
            center = CGPoint(x: CGFloat(values[1]), y: CGFloat(values[2]))
        } else {
            center = nil
        }
        return (angle, center)
    }

    private func rotatePoint(_ point: CGPoint, byDegrees degrees: Double, around center: CGPoint) -> CGPoint {
        let radians = degrees * Double.pi / 180
        let dx = point.x - center.x
        let dy = point.y - center.y
        let cosA = CGFloat(cos(radians))
        let sinA = CGFloat(sin(radians))
        return CGPoint(x: center.x + dx * cosA - dy * sinA,
                       y: center.y + dx * sinA + dy * cosA)
    }

    private func polygonPoints(from pointsStr: String) -> [CGPoint] {
        pointsStr.split(separator: " ").compactMap { pair -> CGPoint? in
            let xy = pair.split(separator: ",")
            guard xy.count == 2, let x = Double(xy[0]), let y = Double(xy[1]) else { return nil }
            return CGPoint(x: x, y: y)
        }
    }

    private func polygonBounds(from points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min()!, minY = ys.min()!, maxX = xs.max()!, maxY = ys.max()!
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
