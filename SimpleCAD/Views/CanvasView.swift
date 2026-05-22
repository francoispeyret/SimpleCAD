import AppKit

// MARK: - CADCanvasView

final class CADCanvasView: NSView {

    // Injected by representable
    var document: CADDocument! {
        didSet { needsDisplay = true }
    }

    // MARK: - Drawing state

    private var isDrawing   = false
    private var drawStart   = CGPoint.zero
    private var currentRect = CGRect.zero

    // MARK: - Selection drag state

    private var isDragging  = false
    private var lastDragPt  = CGPoint.zero

    // MARK: - Pan state (espace + glisser)

    private var isSpaceDown  = false
    private var isPanning    = false
    private var panLastWinPt = CGPoint.zero   // en coordonnées fenêtre
    private var eventMonitor: Any?

    // MARK: - Dimension label hit areas (updated each draw)
    // keyed by shape.id: the clickable CGRect in view coordinates

    private var widthHitRects:  [UUID: CGRect] = [:]
    private var heightHitRects: [UUID: CGRect] = [:]
    private var rotationHandleRects: [UUID: CGRect] = [:]

    // MARK: - Rotation drag state

    private var isRotating = false
    private var rotatingShapeID: UUID?
    private var rotateStartMouseAngle: Double = 0
    private var rotateStartShapeAngle: Double = 0

    // MARK: - Inline dimension editor

    private var dimensionEditor: NSTextField?
    private var editingShapeID:  UUID?
    private enum DimAxis { case width, height }
    private var editingAxis: DimAxis?

    // MARK: - Constants

    private let gridSpacing: CGFloat = 20
    private let handleSize:  CGFloat = 7
    private let dimOffset:   CGFloat = 28  // px from shape edge to dim line
    private let dimExtend:   CGFloat = 6   // extension line overshoot
    private let rotationHandleSize: CGFloat = 18
    private let rotationHandleOffset: CGFloat = 34
    private let rulerThickness: CGFloat = 38
    private let rulerMajorTargetSpacing: CGFloat = 132
    private let rulerMinorDivisions: CGFloat = 5

    // Facteur inverse du zoom : maintient les éléments graphiques à taille constante à l'écran.
    private var invZoom: CGFloat { CGFloat(1.0 / max(document.zoomLevel, 0.01)) }

    var surroundingBackgroundColor: NSColor {
        isDarkAppearance ? NSColor(calibratedWhite: 0.055, alpha: 1)
                         : NSColor.underPageBackgroundColor
    }

    private var canvasBackgroundColor: NSColor {
        isDarkAppearance ? NSColor(calibratedWhite: 0.105, alpha: 1)
                         : NSColor.white
    }

    private var gridColor: NSColor {
        isDarkAppearance ? NSColor(calibratedWhite: 0.22, alpha: 1)
                         : NSColor(calibratedWhite: 0.87, alpha: 1)
    }

    private var overlayFillColor: NSColor {
        isDarkAppearance ? NSColor(calibratedWhite: 0.16, alpha: 0.94)
                         : NSColor.white.withAlphaComponent(0.92)
    }

    private var labelBackgroundColor: NSColor {
        isDarkAppearance ? NSColor(calibratedWhite: 0.12, alpha: 0.88)
                         : NSColor.white.withAlphaComponent(0.85)
    }

    private var rulerBackgroundColor: NSColor {
        isDarkAppearance ? NSColor(calibratedWhite: 0.105, alpha: 0.98)
                         : NSColor(calibratedWhite: 0.965, alpha: 0.98)
    }

    private var rulerBorderColor: NSColor {
        isDarkAppearance ? NSColor(calibratedWhite: 0.24, alpha: 1)
                         : NSColor(calibratedWhite: 0.78, alpha: 1)
    }

    private var rulerTickColor: NSColor {
        isDarkAppearance ? NSColor(calibratedWhite: 0.72, alpha: 1)
                         : NSColor(calibratedWhite: 0.30, alpha: 1)
    }

    private var rulerLabelColor: NSColor {
        isDarkAppearance ? NSColor(calibratedWhite: 0.92, alpha: 1)
                         : NSColor(calibratedWhite: 0.18, alpha: 1)
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // MARK: - Flipped (Y grows downward, same as SVG)

    override var isFlipped: Bool { true }

    // MARK: - Lifecycle (monitor espace global)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            // Surveille espace même sans focus clavier, mais sans consommer l'event
            // pour ne pas gêner les champs de saisie.
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self, event.keyCode == 49 else { return event }
                // Ne pas interférer avec les champs de texte
                let fr = self.window?.firstResponder
                if fr is NSTextView || fr is NSTextField { return event }
                let down = (event.type == .keyDown)
                if down != self.isSpaceDown {
                    self.isSpaceDown = down
                    if !down { self.isPanning = false }
                    self.window?.resetCursorRects()
                }
                // Retourner nil pour absorber l'espace (évite un bip ou une action parasite)
                return nil
            }
        } else {
            if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
            isSpaceDown = false; isPanning = false
        }
        updateAppearanceColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceColors()
    }

    func updateAppearanceColors() {
        enclosingScrollView?.backgroundColor = surroundingBackgroundColor
        needsDisplay = true
    }

    // MARK: - draw(_:)

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        canvasBackgroundColor.setFill()
        bounds.fill()

        if document.showGrid { drawGrid(ctx: ctx) }

        for shape in document.shapes { drawShape(shape, ctx: ctx) }

        if isDrawing, document.currentTool != .select { drawPreview(ctx: ctx) }

        // Reset hit rects each frame
        widthHitRects.removeAll()
        heightHitRects.removeAll()
        rotationHandleRects.removeAll()

        for shape in document.shapes where document.selectedIDs.contains(shape.id) {
            drawSelectionBorder(shape, ctx: ctx)
            if document.showDimensions { drawDimensions(shape, ctx: ctx) }
            drawHandles(shape, ctx: ctx)
            drawRotationHandle(shape, ctx: ctx)
        }

        drawRulers(ctx: ctx)
    }

    // MARK: - Grid

    private func drawGrid(ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(gridColor.cgColor)
        ctx.setLineWidth(0.5)
        var x: CGFloat = 0
        while x <= bounds.width  { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: bounds.height)); x += gridSpacing }
        var y: CGFloat = 0
        while y <= bounds.height { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: bounds.width, y: y));  y += gridSpacing }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Draw shape

    private func drawShape(_ shape: CADShape, ctx: CGContext) {
        let path = shape.bezierPath()
        if shape.fillColor.alpha > 0   { shape.fillColor.nsColor.setFill();   path.fill() }
        if shape.strokeColor.alpha > 0, shape.strokeWidth > 0 {
            shape.strokeColor.nsColor.setStroke()
            path.lineWidth = CGFloat(shape.strokeWidth)
            path.stroke()
        }
    }

    // MARK: - Drawing preview

    private func drawPreview(ctx: CGContext) {
        guard let shapeType = document.currentTool.shapeType else { return }
        let preview = CADShape(type: shapeType, bounds: currentRect, name: "",
                               fillColor: document.fillColor.withAlpha(0.35),
                               strokeColor: document.strokeColor,
                               strokeWidth: document.strokeWidth)
        drawShape(preview, ctx: ctx)
    }

    // MARK: - Selection border

    private func drawSelectionBorder(_ shape: CADShape, ctx: CGContext) {
        ctx.saveGState()
        let z = invZoom
        let path = shape.bezierPath(); path.lineWidth = 1.5 * z
        let dash: [CGFloat] = [5 * z, 3 * z]; path.setLineDash(dash, count: 2, phase: 0)
        NSColor.systemBlue.setStroke(); path.stroke()
        ctx.restoreGState()
    }

    // MARK: - Resize handles

    private func drawHandles(_ shape: CADShape, ctx: CGContext) {
        let hs = handleSize * invZoom
        let b = shape.bounds.standardized
        let midPoints = [
            CGPoint(x: b.midX, y: b.minY),
            CGPoint(x: b.maxX, y: b.midY),
            CGPoint(x: b.midX, y: b.maxY),
            CGPoint(x: b.minX, y: b.midY),
        ].map { rotatePoint($0, byDegrees: shape.rotationAngle, around: shape.center) }
        let pts = shape.rotatedHandlePoints + midPoints

        for pt in pts {
            let r = CGRect(x: pt.x - hs/2, y: pt.y - hs/2, width: hs, height: hs)
            overlayFillColor.setFill(); NSBezierPath(rect: r).fill()
            let bp = NSBezierPath(rect: r); bp.lineWidth = 1.5 * invZoom
            NSColor.systemBlue.setStroke(); bp.stroke()
        }
    }

    // MARK: - Dimension annotations

    private func drawDimensions(_ shape: CADShape, ctx: CGContext) {
        let b = shape.bounds.standardized
        guard b.width > 4, b.height > 4 else { return }

        ctx.saveGState()
        let z = invZoom
        let color = NSColor.systemBlue.withAlphaComponent(0.85)
        color.setStroke(); color.setFill(); ctx.setLineWidth(1.0 * z)

        let xAxis = rotatedUnitX(byDegrees: shape.rotationAngle)
        let yAxis = rotatedUnitY(byDegrees: shape.rotationAngle)
        let pTR = rotatePoint(CGPoint(x: b.maxX, y: b.minY), byDegrees: shape.rotationAngle, around: shape.center)
        let pBR = rotatePoint(CGPoint(x: b.maxX, y: b.maxY), byDegrees: shape.rotationAngle, around: shape.center)
        let pBL = rotatePoint(CGPoint(x: b.minX, y: b.maxY), byDegrees: shape.rotationAngle, around: shape.center)

        let offset = dimOffset * z
        let extend = dimExtend * z

        // ── Width: follows the rotated local X axis, below the shape ─────────
        let wStart = offsetPoint(pBL, along: yAxis, by: offset)
        let wEnd = offsetPoint(pBR, along: yAxis, by: offset)
        strokeLine(ctx, wStart, wEnd)
        strokeLine(ctx, pBL, offsetPoint(pBL, along: yAxis, by: offset + extend))
        strokeLine(ctx, pBR, offsetPoint(pBR, along: yAxis, by: offset + extend))
        drawArrow(ctx, at: wStart, direction: xAxis)
        drawArrow(ctx, at: wEnd, direction: reversed(xAxis))

        let wLabel = document.unit.format(Double(b.width))
        let wLabelCenter = offsetPoint(midpoint(wStart, wEnd), along: yAxis, by: 5 * z)
        let wHit = drawDimensionLabel(
            wLabel,
            at: wLabelCenter,
            angleDegrees: readableLabelAngle(shape.rotationAngle),
            color: color,
            highlighted: editingShapeID == shape.id && editingAxis == .width
        )
        widthHitRects[shape.id] = wHit

        // ── Height: follows the rotated local Y axis, right of the shape ─────
        let hStart = offsetPoint(pTR, along: xAxis, by: offset)
        let hEnd = offsetPoint(pBR, along: xAxis, by: offset)
        strokeLine(ctx, hStart, hEnd)
        strokeLine(ctx, pTR, offsetPoint(pTR, along: xAxis, by: offset + extend))
        strokeLine(ctx, pBR, offsetPoint(pBR, along: xAxis, by: offset + extend))
        drawArrow(ctx, at: hStart, direction: yAxis)
        drawArrow(ctx, at: hEnd, direction: reversed(yAxis))

        let hLabel = document.unit.format(Double(b.height))
        let hLabelCenter = offsetPoint(midpoint(hStart, hEnd), along: xAxis, by: 18 * z)
        let hHit = drawDimensionLabel(
            hLabel,
            at: hLabelCenter,
            angleDegrees: readableLabelAngle(shape.rotationAngle - 90),
            color: color,
            highlighted: editingShapeID == shape.id && editingAxis == .height
        )
        heightHitRects[shape.id] = hHit

        ctx.restoreGState()
    }

    private func drawRotationHandle(_ shape: CADShape, ctx: CGContext) {
        let b = shape.visualBounds
        guard b.width > 4, b.height > 4 else { return }

        ctx.saveGState()
        let z = invZoom
        let size = rotationHandleSize * z
        let center = CGPoint(x: b.midX, y: b.minY - rotationHandleOffset * z)
        let handleRect = CGRect(x: center.x - size/2, y: center.y - size/2,
                                width: size, height: size)

        let color = NSColor.systemBlue.withAlphaComponent(0.9)
        color.setStroke()
        ctx.setLineWidth(1.2 * z)
        strokeLine(ctx, CGPoint(x: b.midX, y: b.minY),
                   CGPoint(x: center.x, y: center.y + size/2))

        overlayFillColor.setFill()
        NSBezierPath(ovalIn: handleRect).fill()
        let ring = NSBezierPath(ovalIn: handleRect)
        ring.lineWidth = 1.5 * z
        color.setStroke()
        ring.stroke()

        let glyphAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12 * z, weight: .semibold),
            .foregroundColor: color
        ]
        let glyph = NSAttributedString(string: "↻", attributes: glyphAttrs)
        let glyphSize = glyph.size()
        glyph.draw(at: CGPoint(x: center.x - glyphSize.width/2,
                               y: center.y - glyphSize.height/2))

        let angle = Int(round(shape.rotationAngle))
        if angle != 0 {
            drawLabel("\(angle)°",
                      at: CGPoint(x: center.x + 26 * z, y: center.y),
                      color: color)
        }

        rotationHandleRects[shape.id] = handleRect.insetBy(dx: -5 * z, dy: -5 * z)
        ctx.restoreGState()
    }

    private func drawDimensionLabel(_ text: String,
                                    at center: CGPoint,
                                    angleDegrees: Double,
                                    color: NSColor,
                                    highlighted: Bool) -> CGRect {
        let margin = 6 * invZoom
        let attrs: [NSAttributedString.Key: Any] = [.font: labelFont()]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let backgroundSize = CGSize(width: textSize.width + margin * 2,
                                    height: textSize.height + margin * 2)

        drawLabelBackground(center: center,
                            size: backgroundSize,
                            angleDegrees: angleDegrees,
                            highlighted: highlighted)
        drawLabelRotated(text, at: center, angleDegrees: angleDegrees, color: color, underline: true)
        return rotatedRectBounds(center: center, size: backgroundSize, angleDegrees: angleDegrees)
    }

    private func drawLabelBackground(center: CGPoint, size: CGSize, angleDegrees: Double, highlighted: Bool) {
        let color = highlighted
            ? NSColor.systemBlue.withAlphaComponent(0.15)
            : labelBackgroundColor
        color.setFill()

        guard let graphicsContext = NSGraphicsContext.current else { return }
        graphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: CGFloat(angleDegrees))
        transform.concat()

        let z = invZoom
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2,
                          width: size.width, height: size.height)
        NSBezierPath(roundedRect: rect.insetBy(dx: z, dy: z),
                     xRadius: 3 * z,
                     yRadius: 3 * z).fill()
        graphicsContext.restoreGraphicsState()
    }

    // MARK: - Rulers

    private func drawRulers(ctx: CGContext) {
        let visible = enclosingScrollView?.contentView.documentVisibleRect ?? bounds
        guard visible.width > 0, visible.height > 0 else { return }

        ctx.saveGState()
        ctx.setShouldAntialias(true)

        let z = invZoom
        let thickness = rulerThickness * z
        let horizontalRect = CGRect(x: visible.minX, y: visible.minY,
                                    width: visible.width, height: thickness)
        let verticalRect = CGRect(x: visible.minX, y: visible.minY,
                                  width: thickness, height: visible.height)
        let cornerRect = CGRect(x: visible.minX, y: visible.minY,
                                width: thickness, height: thickness)

        rulerBackgroundColor.setFill()
        NSBezierPath(rect: horizontalRect).fill()
        NSBezierPath(rect: verticalRect).fill()
        NSBezierPath(rect: cornerRect).fill()

        rulerBorderColor.setStroke()
        ctx.setLineWidth(1 * z)
        strokeLine(ctx,
                   CGPoint(x: horizontalRect.minX, y: horizontalRect.maxY),
                   CGPoint(x: horizontalRect.maxX, y: horizontalRect.maxY))
        strokeLine(ctx,
                   CGPoint(x: verticalRect.maxX, y: verticalRect.minY),
                   CGPoint(x: verticalRect.maxX, y: verticalRect.maxY))

        drawHorizontalRulerTicks(in: horizontalRect, visible: visible)
        drawVerticalRulerTicks(in: verticalRect, visible: visible)

        ctx.restoreGState()
    }

    private func drawHorizontalRulerTicks(in rect: CGRect, visible: CGRect) {
        let z = invZoom
        let majorStep = rulerMajorStepPixels()
        let minorStep = max(majorStep / rulerMinorDivisions, 1)
        var value = floor(visible.minX / minorStep) * minorStep

        while value <= visible.maxX + minorStep {
            let majorRatio = value / majorStep
            let midRatio = value / (majorStep / 2)
            let isMajor = abs(majorRatio.rounded() - majorRatio) < 0.001
            let isMid = !isMajor && abs(midRatio.rounded() - midRatio) < 0.001
            let tickLength = (isMajor ? 16 : (isMid ? 10 : 5)) * z
            let baseline = rect.maxY

            rulerTickColor.setStroke()
            let tick = NSBezierPath()
            tick.move(to: CGPoint(x: value, y: baseline))
            tick.line(to: CGPoint(x: value, y: baseline - tickLength))
            tick.lineWidth = isMajor ? 1.4 * z : 0.8 * z
            tick.stroke()

            if isMajor {
                drawRulerLabel(document.unit.formatValue(Double(value)),
                               at: CGPoint(x: value + 6 * z, y: rect.minY + 7 * z),
                               vertical: false)
            }

            value += minorStep
        }
    }

    private func drawVerticalRulerTicks(in rect: CGRect, visible: CGRect) {
        let z = invZoom
        let majorStep = rulerMajorStepPixels()
        let minorStep = max(majorStep / rulerMinorDivisions, 1)
        var value = floor(visible.minY / minorStep) * minorStep

        while value <= visible.maxY + minorStep {
            let majorRatio = value / majorStep
            let midRatio = value / (majorStep / 2)
            let isMajor = abs(majorRatio.rounded() - majorRatio) < 0.001
            let isMid = !isMajor && abs(midRatio.rounded() - midRatio) < 0.001
            let tickLength = (isMajor ? 16 : (isMid ? 10 : 5)) * z
            let baseline = rect.maxX

            rulerTickColor.setStroke()
            let tick = NSBezierPath()
            tick.move(to: CGPoint(x: baseline, y: value))
            tick.line(to: CGPoint(x: baseline - tickLength, y: value))
            tick.lineWidth = isMajor ? 1.4 * z : 0.8 * z
            tick.stroke()

            if isMajor {
                drawRulerLabel(document.unit.formatValue(Double(value)),
                               at: CGPoint(x: rect.minX + 18 * z, y: value + 6 * z),
                               vertical: true)
            }

            value += minorStep
        }
    }

    private func rulerMajorStepPixels() -> CGFloat {
        let targetDocumentPixels = max(rulerMajorTargetSpacing * invZoom, 1)
        let targetUnits = max(document.unit.fromPixels(Double(targetDocumentPixels)), 0.000001)
        return CGFloat(document.unit.toPixels(niceRulerStep(targetUnits)))
    }

    private func niceRulerStep(_ value: Double) -> Double {
        let exponent = floor(log10(value))
        let base = pow(10, exponent)
        let fraction = value / base

        if fraction <= 1 { return base }
        if fraction <= 2 { return 2 * base }
        if fraction <= 5 { return 5 * base }
        return 10 * base
    }

    private func drawRulerLabel(_ text: String, at point: CGPoint, vertical: Bool) {
        let z = invZoom
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12 * z, weight: .medium),
            .foregroundColor: rulerLabelColor
        ]
        let string = NSAttributedString(string: text, attributes: attrs)
        let size = string.size()

        if vertical {
            NSGraphicsContext.current?.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: point.x, yBy: point.y + size.width / 2)
            transform.rotate(byDegrees: -90)
            transform.concat()
            string.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
            NSGraphicsContext.current?.restoreGraphicsState()
        } else {
            string.draw(at: point)
        }
    }

    private func rulerRects() -> (horizontal: CGRect, vertical: CGRect)? {
        let visible = enclosingScrollView?.contentView.documentVisibleRect ?? bounds
        guard visible.width > 0, visible.height > 0 else { return nil }
        let thickness = rulerThickness * invZoom
        return (
            CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: thickness),
            CGRect(x: visible.minX, y: visible.minY, width: thickness, height: visible.height)
        )
    }

    private func pointIsInRuler(_ point: CGPoint) -> Bool {
        guard let rects = rulerRects() else { return false }
        return rects.horizontal.contains(point) || rects.vertical.contains(point)
    }

    // MARK: - Drawing helpers

    private func strokeLine(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint) {
        ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
    }

    private func rotatedUnitX(byDegrees degrees: Double) -> CGVector {
        let radians = degrees * Double.pi / 180
        return CGVector(dx: CGFloat(cos(radians)), dy: CGFloat(sin(radians)))
    }

    private func rotatedUnitY(byDegrees degrees: Double) -> CGVector {
        let radians = degrees * Double.pi / 180
        return CGVector(dx: CGFloat(-sin(radians)), dy: CGFloat(cos(radians)))
    }

    private func offsetPoint(_ point: CGPoint, along vector: CGVector, by distance: CGFloat) -> CGPoint {
        CGPoint(x: point.x + vector.dx * distance,
                y: point.y + vector.dy * distance)
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private func reversed(_ vector: CGVector) -> CGVector {
        CGVector(dx: -vector.dx, dy: -vector.dy)
    }

    private func readableLabelAngle(_ angle: Double) -> Double {
        var normalized = CADShape.normalizedRotation(angle)
        if normalized > 90 { normalized -= 180 }
        if normalized < -90 { normalized += 180 }
        return normalized
    }

    private func rotatedRectBounds(center: CGPoint, size: CGSize, angleDegrees: Double) -> CGRect {
        let halfW = size.width / 2
        let halfH = size.height / 2
        let corners = [
            CGPoint(x: center.x - halfW, y: center.y - halfH),
            CGPoint(x: center.x + halfW, y: center.y - halfH),
            CGPoint(x: center.x + halfW, y: center.y + halfH),
            CGPoint(x: center.x - halfW, y: center.y + halfH)
        ].map { rotatePoint($0, byDegrees: angleDegrees, around: center) }
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!,
                      width: xs.max()! - xs.min()!,
                      height: ys.max()! - ys.min()!)
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

    private func angleDegrees(from center: CGPoint, to point: CGPoint) -> Double {
        atan2(Double(point.y - center.y), Double(point.x - center.x)) * 180 / Double.pi
    }

    private func drawArrow(_ ctx: CGContext, at p: CGPoint, direction: CGVector) {
        let s: CGFloat = 6 * invZoom
        let length = max(sqrt(direction.dx * direction.dx + direction.dy * direction.dy), 0.0001)
        let dir = CGVector(dx: direction.dx / length, dy: direction.dy / length)
        let normal = CGVector(dx: -dir.dy, dy: dir.dx)
        let path = NSBezierPath()
        path.move(to: offsetPoint(p, along: dir, by: s))
        path.line(to: offsetPoint(p, along: normal, by: s / 2))
        path.line(to: offsetPoint(p, along: normal, by: -s / 2))
        path.close(); path.fill()
    }

    private func labelFont() -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 9.5 * invZoom, weight: .regular)
    }

    private func drawLabel(_ text: String, at center: CGPoint, color: NSColor, underline: Bool = false) {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: labelFont(), .foregroundColor: color
        ]
        if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        let str  = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        str.draw(at: CGPoint(x: center.x - size.width/2, y: center.y - size.height/2))
    }

    private func drawLabelRotated(_ text: String,
                                  at center: CGPoint,
                                  angleDegrees: Double,
                                  color: NSColor,
                                  underline: Bool = false) {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: labelFont(), .foregroundColor: color
        ]
        if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()

        NSGraphicsContext.current?.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: CGFloat(angleDegrees))
        transform.concat()
        str.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    // MARK: - Inline dimension editor

    private func showDimensionEditor(for shape: CADShape, axis: DimAxis) {
        dismissDimensionEditor()

        editingShapeID = shape.id
        editingAxis    = axis

        let currentPx: Double
        let hitRect: CGRect?
        switch axis {
        case .width:
            currentPx = Double(shape.bounds.width)
            hitRect   = widthHitRects[shape.id]
        case .height:
            currentPx = Double(shape.bounds.height)
            hitRect   = heightHitRects[shape.id]
        }

        guard let rect = hitRect else { return }

        // Largeur adaptée à l'unité ; toute la géométrie est mise à l'échelle inverse du zoom
        let z = invZoom
        let tfW: CGFloat = max(72, CGFloat(14 + document.unit.decimals * 8)) * z
        let tfH: CGFloat = 20 * z
        let tfRect = CGRect(
            x: rect.midX - tfW/2,
            y: rect.midY - tfH/2,
            width: tfW, height: tfH
        )

        let tf = NSTextField(frame: tfRect)
        tf.stringValue   = document.unit.formatValue(currentPx)
        tf.font          = NSFont.monospacedDigitSystemFont(ofSize: 11 * z, weight: .medium)
        tf.alignment     = .center
        tf.bezelStyle    = .roundedBezel
        tf.focusRingType = .default
        tf.delegate      = self
        addSubview(tf)
        window?.makeFirstResponder(tf)
        tf.selectText(nil)

        dimensionEditor = tf
        needsDisplay = true
    }

    private func dismissDimensionEditor() {
        dimensionEditor?.removeFromSuperview()
        dimensionEditor = nil
        editingShapeID  = nil
        editingAxis     = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func commitDimensionEdit(text: String) {
        guard let id = editingShapeID,
              let axis = editingAxis,
              var shape = document.shapes.first(where: { $0.id == id })
        else { dismissDimensionEditor(); return }

        // Accept both "." and "," as decimal separator
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        guard let valueInUnit = Double(cleaned), valueInUnit > 0 else {
            dismissDimensionEditor(); return
        }

        let px = document.unit.toPixels(valueInUnit)
        switch axis {
        case .width:  shape.bounds.size.width  = CGFloat(px)
        case .height: shape.bounds.size.height = CGFloat(px)
        }

        document.updateShape(shape)
        dismissDimensionEditor()
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        // ── Pan avec espace ───────────────────────────────────────────
        if isSpaceDown {
            isPanning    = true
            panLastWinPt = event.locationInWindow
            NSCursor.closedHand.set()
            return
        }

        let pt = convert(event.locationInWindow, from: nil)
        if pointIsInRuler(pt) { return }

        // ── Rotation handle hit test ────────────────────────────────
        for shape in document.shapes.reversed() where document.selectedIDs.contains(shape.id) {
            if let r = rotationHandleRects[shape.id], r.contains(pt) {
                startRotation(for: shape, at: pt)
                return
            }
        }

        // ── Dimension label hit test (only when a shape is selected) ──
        if document.showDimensions {
            for shape in document.shapes where document.selectedIDs.contains(shape.id) {
                if let r = widthHitRects[shape.id],  r.contains(pt) {
                    showDimensionEditor(for: shape, axis: .width);  return
                }
                if let r = heightHitRects[shape.id], r.contains(pt) {
                    showDimensionEditor(for: shape, axis: .height); return
                }
            }
        }

        // Dismiss any open editor on other clicks
        if dimensionEditor != nil { dismissDimensionEditor() }

        if document.currentTool == .select {
            handleSelectDown(pt: pt, event: event)
        } else {
            isDrawing = true
            drawStart = pt
            currentRect = .zero
        }
    }

    override func mouseDragged(with event: NSEvent) {

        if isRotating {
            let pt = convert(event.locationInWindow, from: nil)
            updateRotation(to: pt, event: event)
            return
        }

        // ── Pan ───────────────────────────────────────────────────────
        if isPanning {
            let win = event.locationInWindow
            let dx = win.x - panLastWinPt.x   // positif = tiré vers la droite
            let dy = win.y - panLastWinPt.y   // positif = tiré vers le haut (coordonnées fenêtre Y↑)
            panLastWinPt = win

            if let sv = enclosingScrollView {
                let clip = sv.contentView
                var origin = clip.bounds.origin
                // La vue est flipped (Y↓), la fenêtre a Y↑ :
                //   tirer droite (dx>0) → on voit le contenu à gauche → origin.x diminue
                //   tirer haut  (dy>0) → on voit le contenu en haut  → origin.y diminue (flipped)
                origin.x -= dx
                origin.y += dy
                let clamped = clip.constrainBoundsRect(
                    NSRect(origin: origin, size: clip.bounds.size)
                ).origin
                clip.scroll(to: clamped)
                sv.reflectScrolledClipView(clip)
            }
            return
        }

        let pt = convert(event.locationInWindow, from: nil)

        if document.currentTool == .select {
            if isDragging, !document.selectedIDs.isEmpty {
                let delta = CGSize(width: pt.x - lastDragPt.x, height: pt.y - lastDragPt.y)
                document.moveSelectedShapes(by: delta)
                lastDragPt = pt
                needsDisplay = true
            }
        } else if isDrawing {
            var r = CGRect(
                x: min(drawStart.x, pt.x), y: min(drawStart.y, pt.y),
                width: abs(pt.x - drawStart.x), height: abs(pt.y - drawStart.y)
            )
            if document.currentTool.constrainedToSquare || event.modifierFlags.contains(.shift) {
                let side = min(r.width, r.height)
                r.origin.x = drawStart.x <= pt.x ? drawStart.x : drawStart.x - side
                r.origin.y = drawStart.y <= pt.y ? drawStart.y : drawStart.y - side
                r.size = CGSize(width: side, height: side)
            }
            currentRect = r
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isRotating {
            finishRotation()
            return
        }

        // ── Fin du pan ────────────────────────────────────────────────
        if isPanning {
            isPanning = false
            window?.resetCursorRects()   // repasse en main ouverte si espace encore tenu
            return
        }

        if document.currentTool == .select {
            document.commitMove()
            isDragging = false
        } else if isDrawing {
            isDrawing = false
            if currentRect.width > 4, currentRect.height > 4 {
                let type = document.currentTool.shapeType!
                let shape = CADShape(type: type, bounds: currentRect,
                                     name: document.nextName(for: type),
                                     fillColor: document.fillColor,
                                     strokeColor: document.strokeColor,
                                     strokeWidth: document.strokeWidth)
                document.addShape(shape)
                document.selectShape(id: shape.id)
            }
            currentRect = .zero
            needsDisplay = true
        }
    }

    private func handleSelectDown(pt: CGPoint, event: NSEvent) {
        let hit = document.shapes.reversed().first { $0.contains(pt) }
        if let shape = hit {
            document.selectShape(id: shape.id, additive: event.modifierFlags.contains(.shift))
            isDragging = true; lastDragPt = pt
            document.beginMove()
        } else {
            document.deselectAll()
        }
        needsDisplay = true
    }

    private func startRotation(for shape: CADShape, at point: CGPoint) {
        if dimensionEditor != nil { dismissDimensionEditor() }

        isRotating = true
        rotatingShapeID = shape.id
        rotateStartMouseAngle = angleDegrees(from: shape.center, to: point)
        rotateStartShapeAngle = shape.rotationAngle
        document.beginRotation()
        NSCursor.closedHand.set()
    }

    private func updateRotation(to point: CGPoint, event: NSEvent) {
        guard let id = rotatingShapeID,
              let shape = document.shapes.first(where: { $0.id == id }) else { return }

        let currentAngle = angleDegrees(from: shape.center, to: point)
        var newAngle = rotateStartShapeAngle + currentAngle - rotateStartMouseAngle
        if event.modifierFlags.contains(.shift) {
            newAngle = (newAngle / 15).rounded() * 15
        }

        document.rotateShape(id: id, to: newAngle)
        needsDisplay = true
    }

    private func finishRotation() {
        document.commitRotation()
        isRotating = false
        rotatingShapeID = nil
        window?.resetCursorRects()
        needsDisplay = true
    }

    // MARK: - Keyboard

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117:                                                           // Delete
            document.removeSelected(); needsDisplay = true
        case 53:                                                                // Escape
            dismissDimensionEditor()
        case 123:                                                               // ←
            document.beginMove()
            document.moveSelectedShapes(by: CGSize(width: -1, height: 0)); needsDisplay = true
        case 124:                                                               // →
            document.beginMove()
            document.moveSelectedShapes(by: CGSize(width:  1, height: 0)); needsDisplay = true
        case 125:                                                               // ↓
            document.beginMove()
            document.moveSelectedShapes(by: CGSize(width:  0, height: 1)); needsDisplay = true
        case 126:                                                               // ↑
            document.beginMove()
            document.moveSelectedShapes(by: CGSize(width:  0, height: -1)); needsDisplay = true
        default:
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        switch event.keyCode {
        case 123, 124, 125, 126:   // Touches fléchées : valider le déplacement
            document.commitMove()
        default:
            super.keyUp(with: event)
        }
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        if isPanning {
            addCursorRect(bounds, cursor: .closedHand)
        } else if isSpaceDown {
            addCursorRect(bounds, cursor: .openHand)
        } else {
            addCursorRect(bounds, cursor: document.currentTool == .select ? .arrow : .crosshair)
            if document.currentTool == .select {
                for rect in rotationHandleRects.values {
                    addCursorRect(rect, cursor: .openHand)
                }
            }
        }
    }
}

// MARK: - NSTextFieldDelegate

extension CADCanvasView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            commitDimensionEdit(text: (control as? NSTextField)?.stringValue ?? "")
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            dismissDimensionEditor()
            return true
        }
        return false
    }
}
