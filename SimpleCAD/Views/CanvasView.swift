import AppKit

// MARK: - CADCanvasView

final class CADCanvasView: NSView {

    private static var resizeCursorCache: [Int: NSCursor] = [:]

    // Injected by representable
    var document: CADDocument! {
        didSet { needsDisplay = true }
    }

    // MARK: - Drawing state

    private var isDrawing   = false
    private var drawStart   = CGPoint.zero
    private var currentRect = CGRect.zero
    private var currentRotationAngle: Double = 0

    // MARK: - Selection drag state

    private var isDragging  = false
    private var lastDragPt  = CGPoint.zero
    private var isMarqueeSelecting = false
    private var marqueeStart = CGPoint.zero
    private var marqueeRect = CGRect.zero
    private var marqueeBaseSelection: Set<UUID> = []
    private var marqueeAddsToSelection = false
    private var dragStartPt = CGPoint.zero
    private var dragBaseShapes: [UUID: CADShape] = [:]

    // MARK: - Resize drag state

    private var resizeHandleRects: [UUID: [ResizeHandle: CGRect]] = [:]
    private var isResizing = false
    private var resizingShapeID: UUID?
    private var resizingHandle: ResizeHandle?
    private var resizeStartShape: CADShape?

    // MARK: - Point editing state

    private struct PointHandleKey: Hashable {
        var shapeID: UUID
        var pointIndex: Int
    }

    private struct PointEditTarget {
        var shapeID: UUID
        var pointIndex: Int
    }

    private var pointHandleRects: [PointHandleKey: CGRect] = [:]
    private var isEditingPoint = false
    private var pointEditTarget: PointEditTarget?

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

    // MARK: - Construction guides

    private struct RotationHandleGeometry {
        var anchor: CGPoint
        var center: CGPoint
        var labelPoint: CGPoint
        var handleRect: CGRect
        var connectorEnd: CGPoint
    }

    private var activeConstructionGuides: [ConstructionGuide] = []

    // MARK: - Inline dimension editor

    private var dimensionEditor: NSTextField?
    private var editingShapeID:  UUID?
    private enum DimAxis { case width, height }
    private var editingAxis: DimAxis?

    // MARK: - Constants

    private let handleSize:  CGFloat = 7
    private let pointHandleSize: CGFloat = 8
    private let dimOffset:   CGFloat = 28  // px from shape edge to dim line
    private let dimExtend:   CGFloat = 6   // extension line overshoot
    private let rotationHandleSize: CGFloat = 18
    private let rotationHandleOffset: CGFloat = 34
    private let horizontalRulerHeight: CGFloat = 38 * 0.34
    private let verticalRulerWidth: CGFloat = 38 * 0.34
    private let rulerMajorTargetSpacing: CGFloat = 132
    private let rulerMinorDivisions: CGFloat = 5
    private let snapToleranceScreen: CGFloat = 8
    private let constructionGuidePadding: CGFloat = 42
    private let minimumResizeSide: CGFloat = 6

    // Facteur inverse du zoom : maintient les éléments graphiques à taille constante à l'écran.
    private var invZoom: CGFloat { CGFloat(1.0 / max(document.zoomLevel, 0.01)) }

    private var gridSpacing: CGFloat { document.gridDisplayMode.spacing }

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

        if document.gridDisplayMode != .none { drawGrid(ctx: ctx) }

        for shape in document.shapes { drawShape(shape, ctx: ctx) }

        if !activeConstructionGuides.isEmpty { drawConstructionGuides(ctx: ctx) }

        if isDrawing, document.currentTool.shapeType != nil { drawPreview(ctx: ctx) }

        // Reset hit rects each frame
        widthHitRects.removeAll()
        heightHitRects.removeAll()
        rotationHandleRects.removeAll()
        resizeHandleRects.removeAll()
        pointHandleRects.removeAll()

        for shape in document.shapes where shouldDrawDimensions(for: shape) && !document.selectedIDs.contains(shape.id) {
            drawDimensions(shape, ctx: ctx)
        }

        for shape in document.shapes where document.selectedIDs.contains(shape.id) {
            drawSelectionBorder(shape, ctx: ctx)
            if shouldDrawDimensions(for: shape) { drawDimensions(shape, ctx: ctx) }
            if document.currentTool == .pointSelect {
                drawPointHandles(shape, ctx: ctx)
            } else {
                drawHandles(shape, ctx: ctx)
                drawRotationHandle(shape, ctx: ctx)
            }
        }

        if isMarqueeSelecting { drawSelectionMarquee(ctx: ctx) }

        drawRulers(ctx: ctx)
    }

    // MARK: - Grid

    private func drawGrid(ctx: CGContext) {
        guard gridSpacing > 0 else { return }

        ctx.saveGState()
        ctx.setStrokeColor(gridColor.cgColor)
        ctx.setLineWidth(document.gridDisplayMode == .wide ? 0.65 : 0.5)
        let origin = document.rulerOrigin
        var x = origin.x + floor((bounds.minX - origin.x) / gridSpacing) * gridSpacing
        while x <= bounds.maxX {
            ctx.move(to: CGPoint(x: x, y: bounds.minY))
            ctx.addLine(to: CGPoint(x: x, y: bounds.maxY))
            x += gridSpacing
        }
        var y = origin.y + floor((bounds.minY - origin.y) / gridSpacing) * gridSpacing
        while y <= bounds.maxY {
            ctx.move(to: CGPoint(x: bounds.minX, y: y))
            ctx.addLine(to: CGPoint(x: bounds.maxX, y: y))
            y += gridSpacing
        }
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
                               strokeWidth: document.strokeWidth,
                               rotationAngle: currentRotationAngle)
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

    private func drawSelectionMarquee(ctx: CGContext) {
        guard marqueeRect.width > 0, marqueeRect.height > 0 else { return }

        ctx.saveGState()
        let z = invZoom
        let rect = marqueeRect.standardized

        NSColor.systemBlue.withAlphaComponent(isDarkAppearance ? 0.16 : 0.10).setFill()
        NSBezierPath(rect: rect).fill()

        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.2 * z
        path.setLineDash([6 * z, 3 * z], count: 2, phase: 0)
        NSColor.systemBlue.setStroke()
        path.stroke()
        ctx.restoreGState()
    }

    private func drawConstructionGuides(ctx: CGContext) {
        let z = invZoom
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.systemTeal.withAlphaComponent(isDarkAppearance ? 0.95 : 0.85).cgColor)
        ctx.setLineWidth(1.2 * z)
        ctx.setLineDash(phase: 0, lengths: [5 * z, 4 * z])

        for guide in activeConstructionGuides {
            switch guide.orientation {
            case .vertical:
                ctx.move(to: CGPoint(x: guide.position, y: guide.start))
                ctx.addLine(to: CGPoint(x: guide.position, y: guide.end))
            case .horizontal:
                ctx.move(to: CGPoint(x: guide.start, y: guide.position))
                ctx.addLine(to: CGPoint(x: guide.end, y: guide.position))
            }
        }

        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Resize handles

    private func resizeHandlePositions(for shape: CADShape) -> [(ResizeHandle, CGPoint)] {
        let b = shape.bounds.standardized
        return ResizeHandle.allCases.map { handle in
            let point = handle.point(in: b)
            return (handle, rotatePoint(point, byDegrees: shape.rotationAngle, around: shape.center))
        }
    }

    private func calculatedResizeHandleRects(for shape: CADShape) -> [ResizeHandle: CGRect] {
        let hs = handleSize * invZoom
        return Dictionary(uniqueKeysWithValues: resizeHandlePositions(for: shape).map { handle, pt in
            let rect = CGRect(x: pt.x - hs/2, y: pt.y - hs/2, width: hs, height: hs)
            return (handle, rect.insetBy(dx: -5 * invZoom, dy: -5 * invZoom))
        })
    }

    private func drawHandles(_ shape: CADShape, ctx: CGContext) {
        let hs = handleSize * invZoom
        var hitRects: [ResizeHandle: CGRect] = [:]

        for (handle, pt) in resizeHandlePositions(for: shape) {
            let r = CGRect(x: pt.x - hs/2, y: pt.y - hs/2, width: hs, height: hs)
            overlayFillColor.setFill(); NSBezierPath(rect: r).fill()
            let bp = NSBezierPath(rect: r); bp.lineWidth = 1.5 * invZoom
            NSColor.systemBlue.setStroke(); bp.stroke()
            hitRects[handle] = r.insetBy(dx: -5 * invZoom, dy: -5 * invZoom)
        }

        resizeHandleRects[shape.id] = hitRects
    }

    private func drawPointHandles(_ shape: CADShape, ctx: CGContext) {
        let points = shape.editablePoints()
        guard !points.isEmpty else { return }

        ctx.saveGState()
        let hs = pointHandleSize * invZoom

        for (index, point) in points.enumerated() {
            let rect = CGRect(x: point.x - hs / 2,
                              y: point.y - hs / 2,
                              width: hs,
                              height: hs)
            overlayFillColor.setFill()
            NSBezierPath(ovalIn: rect).fill()

            let outline = NSBezierPath(ovalIn: rect)
            outline.lineWidth = 1.6 * invZoom
            NSColor.systemBlue.setStroke()
            outline.stroke()

            let key = PointHandleKey(shapeID: shape.id, pointIndex: index)
            pointHandleRects[key] = rect.insetBy(dx: -6 * invZoom, dy: -6 * invZoom)
        }

        ctx.restoreGState()
    }

    // MARK: - Dimension annotations

    private func shouldDrawDimensions(for shape: CADShape) -> Bool {
        switch document.dimensionDisplayMode {
        case .none:
            return false
        case .selected:
            return document.selectedIDs.contains(shape.id)
        case .all:
            return true
        }
    }

    private func drawDimensions(_ shape: CADShape, ctx: CGContext) {
        let b = shape.bounds.standardized
        if shape.type == .line {
            drawLineDimensions(shape, bounds: b, ctx: ctx)
            return
        }
        if shape.type == .circle || shape.type == .ellipse {
            drawRoundShapeDimensions(shape, bounds: b, ctx: ctx)
            return
        }
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

    private func drawRoundShapeDimensions(_ shape: CADShape, bounds b: CGRect, ctx: CGContext) {
        guard b.width > 4, b.height > 4 else { return }

        ctx.saveGState()
        let z = invZoom
        let color = NSColor.systemBlue.withAlphaComponent(0.85)
        color.setStroke()
        color.setFill()
        ctx.setLineWidth(1.0 * z)

        let center = shape.center
        let xAxis = rotatedUnitX(byDegrees: shape.rotationAngle)
        let yAxis = rotatedUnitY(byDegrees: shape.rotationAngle)
        let left = offsetPoint(center, along: xAxis, by: -b.width / 2)
        let right = offsetPoint(center, along: xAxis, by: b.width / 2)

        strokeLine(ctx, left, right)
        drawArrow(ctx, at: left, direction: xAxis)
        drawArrow(ctx, at: right, direction: reversed(xAxis))

        let circleLike = isCircleLike(b)
        let wLabelCenter: CGPoint
        if circleLike {
            wLabelCenter = offsetPoint(center, along: yAxis, by: -14 * z)
        } else {
            let shifted = offsetPoint(center, along: xAxis, by: -diameterLabelShift(for: b.width))
            wLabelCenter = offsetPoint(shifted, along: yAxis, by: 20 * z)
        }
        widthHitRects[shape.id] = drawDimensionLabel(
            diameterLabel(for: b.width),
            at: wLabelCenter,
            angleDegrees: readableLabelAngle(shape.rotationAngle),
            color: color,
            highlighted: editingShapeID == shape.id && editingAxis == .width
        )

        if !circleLike {
            let top = offsetPoint(center, along: yAxis, by: -b.height / 2)
            let bottom = offsetPoint(center, along: yAxis, by: b.height / 2)

            strokeLine(ctx, top, bottom)
            drawArrow(ctx, at: top, direction: yAxis)
            drawArrow(ctx, at: bottom, direction: reversed(yAxis))

            let shifted = offsetPoint(center, along: yAxis, by: -diameterLabelShift(for: b.height))
            let hLabelCenter = offsetPoint(shifted, along: xAxis, by: 30 * z)
            heightHitRects[shape.id] = drawDimensionLabel(
                diameterLabel(for: b.height),
                at: hLabelCenter,
                angleDegrees: readableLabelAngle(shape.rotationAngle - 90),
                color: color,
                highlighted: editingShapeID == shape.id && editingAxis == .height
            )
        }

        ctx.restoreGState()
    }

    private func isCircleLike(_ bounds: CGRect) -> Bool {
        abs(bounds.width - bounds.height) <= max(1 * invZoom, 0.5)
    }

    private func diameterLabelShift(for length: CGFloat) -> CGFloat {
        let z = invZoom
        return min(max(length * 0.24, 18 * z), max(length / 2 - 8 * z, 0))
    }

    private func diameterLabel(for value: CGFloat) -> String {
        "Ø \(document.unit.format(Double(value)))"
    }

    private func drawLineDimensions(_ shape: CADShape, bounds b: CGRect, ctx: CGContext) {
        guard b.width > 4, let endpoints = shape.lineEndpoints else { return }

        ctx.saveGState()
        let z = invZoom
        let color = NSColor.systemBlue.withAlphaComponent(0.85)
        color.setStroke()
        color.setFill()
        ctx.setLineWidth(1.0 * z)

        let xAxis = rotatedUnitX(byDegrees: shape.rotationAngle)
        let yAxis = rotatedUnitY(byDegrees: shape.rotationAngle)
        let offset = dimOffset * z
        let extend = dimExtend * z
        let start = endpoints.start
        let end = endpoints.end
        let dStart = offsetPoint(start, along: yAxis, by: offset)
        let dEnd = offsetPoint(end, along: yAxis, by: offset)

        strokeLine(ctx, dStart, dEnd)
        strokeLine(ctx, start, offsetPoint(start, along: yAxis, by: offset + extend))
        strokeLine(ctx, end, offsetPoint(end, along: yAxis, by: offset + extend))
        drawArrow(ctx, at: dStart, direction: xAxis)
        drawArrow(ctx, at: dEnd, direction: reversed(xAxis))

        let label = document.unit.format(Double(b.width))
        let labelCenter = offsetPoint(midpoint(dStart, dEnd), along: yAxis, by: 5 * z)
        widthHitRects[shape.id] = drawDimensionLabel(
            label,
            at: labelCenter,
            angleDegrees: readableLabelAngle(shape.rotationAngle),
            color: color,
            highlighted: editingShapeID == shape.id && editingAxis == .width
        )

        ctx.restoreGState()
    }

    private func drawRotationHandle(_ shape: CADShape, ctx: CGContext) {
        guard let geometry = rotationHandleGeometry(for: shape) else { return }

        ctx.saveGState()
        let z = invZoom

        let color = NSColor.systemBlue.withAlphaComponent(0.9)
        color.setStroke()
        ctx.setLineWidth(1.2 * z)
        strokeLine(ctx, geometry.anchor, geometry.connectorEnd)

        overlayFillColor.setFill()
        NSBezierPath(ovalIn: geometry.handleRect).fill()
        let ring = NSBezierPath(ovalIn: geometry.handleRect)
        ring.lineWidth = 1.5 * z
        color.setStroke()
        ring.stroke()

        let glyphAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12 * z, weight: .semibold),
            .foregroundColor: color
        ]
        let glyph = NSAttributedString(string: "↻", attributes: glyphAttrs)
        let glyphSize = glyph.size()
        glyph.draw(at: CGPoint(x: geometry.center.x - glyphSize.width/2,
                               y: geometry.center.y - glyphSize.height/2))

        let angle = Int(round(shape.rotationAngle))
        if angle != 0 {
            drawLabel("\(angle)°",
                      at: geometry.labelPoint,
                      color: color)
        }

        rotationHandleRects[shape.id] = rotationHandleHitRect(for: shape)
        ctx.restoreGState()
    }

    private func rotationHandleGeometry(for shape: CADShape) -> RotationHandleGeometry? {
        let b = shape.bounds.standardized
        guard b.width > 4, b.height > 4 else { return nil }

        let z = invZoom
        let size = rotationHandleSize * z
        let xAxis = rotatedUnitX(byDegrees: shape.rotationAngle)
        let yAxis = rotatedUnitY(byDegrees: shape.rotationAngle)
        let anchor = rotatePoint(CGPoint(x: b.midX, y: b.minY),
                                 byDegrees: shape.rotationAngle,
                                 around: shape.center)
        let center = offsetPoint(anchor, along: yAxis, by: -rotationHandleOffset * z)
        let handleRect = CGRect(x: center.x - size / 2,
                                y: center.y - size / 2,
                                width: size,
                                height: size)
        return RotationHandleGeometry(
            anchor: anchor,
            center: center,
            labelPoint: offsetPoint(center, along: xAxis, by: 26 * z),
            handleRect: handleRect,
            connectorEnd: offsetPoint(center, along: yAxis, by: size / 2)
        )
    }

    private func rotationHandleHitRect(for shape: CADShape) -> CGRect? {
        rotationHandleGeometry(for: shape)?.handleRect.insetBy(dx: -5 * invZoom, dy: -5 * invZoom)
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
        let horizontalHeight = horizontalRulerHeight * z
        let verticalWidth = verticalRulerWidth * z
        let horizontalRect = CGRect(x: visible.minX, y: visible.minY,
                                    width: visible.width, height: horizontalHeight)
        let verticalRect = CGRect(x: visible.minX, y: visible.minY,
                                  width: verticalWidth, height: visible.height)
        let cornerRect = CGRect(x: visible.minX, y: visible.minY,
                                width: verticalWidth, height: horizontalHeight)

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
        let originX = document.rulerOrigin.x
        var value = originX + floor((visible.minX - originX) / minorStep) * minorStep

        while value <= visible.maxX + minorStep {
            let relativeValue = value - originX
            let majorRatio = relativeValue / majorStep
            let midRatio = relativeValue / (majorStep / 2)
            let isMajor = abs(majorRatio.rounded() - majorRatio) < 0.001
            let isMid = !isMajor && abs(midRatio.rounded() - midRatio) < 0.001
            let tickLength = rect.height * (isMajor ? 0.55 : (isMid ? 0.38 : 0.24))
            let baseline = rect.maxY

            rulerTickColor.setStroke()
            let tick = NSBezierPath()
            tick.move(to: CGPoint(x: value, y: baseline))
            tick.line(to: CGPoint(x: value, y: baseline - tickLength))
            tick.lineWidth = isMajor ? 1.4 * z : 0.8 * z
            tick.stroke()

            if isMajor {
                drawRulerLabel(document.unit.formatValue(Double(rulerLabelValue(relativeValue))),
                               at: CGPoint(x: value + 4 * z, y: rect.minY + 1.5 * z),
                               vertical: false)
            }

            value += minorStep
        }
    }

    private func drawVerticalRulerTicks(in rect: CGRect, visible: CGRect) {
        let z = invZoom
        let majorStep = rulerMajorStepPixels()
        let minorStep = max(majorStep / rulerMinorDivisions, 1)
        let originY = document.rulerOrigin.y
        var value = originY + floor((visible.minY - originY) / minorStep) * minorStep

        while value <= visible.maxY + minorStep {
            let relativeValue = value - originY
            let majorRatio = relativeValue / majorStep
            let midRatio = relativeValue / (majorStep / 2)
            let isMajor = abs(majorRatio.rounded() - majorRatio) < 0.001
            let isMid = !isMajor && abs(midRatio.rounded() - midRatio) < 0.001
            let tickLength = rect.width * (isMajor ? 0.55 : (isMid ? 0.38 : 0.24))
            let baseline = rect.maxX

            rulerTickColor.setStroke()
            let tick = NSBezierPath()
            tick.move(to: CGPoint(x: baseline, y: value))
            tick.line(to: CGPoint(x: baseline - tickLength, y: value))
            tick.lineWidth = isMajor ? 1.4 * z : 0.8 * z
            tick.stroke()

            if isMajor {
                drawRulerLabel(document.unit.formatValue(Double(rulerLabelValue(relativeValue))),
                               at: CGPoint(x: rect.midX, y: value + 4 * z),
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

    private func rulerLabelValue(_ value: CGFloat) -> CGFloat {
        abs(value) < 0.0001 ? 0 : value
    }

    private func drawRulerLabel(_ text: String, at point: CGPoint, vertical: Bool) {
        let z = invZoom
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8 * z, weight: .medium),
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
        let horizontalHeight = horizontalRulerHeight * invZoom
        let verticalWidth = verticalRulerWidth * invZoom
        return (
            CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: horizontalHeight),
            CGRect(x: visible.minX, y: visible.minY, width: verticalWidth, height: visible.height)
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
        CADGeometry.rotatedUnitX(byDegrees: degrees)
    }

    private func rotatedUnitY(byDegrees degrees: Double) -> CGVector {
        CADGeometry.rotatedUnitY(byDegrees: degrees)
    }

    private func offsetPoint(_ point: CGPoint, along vector: CGVector, by distance: CGFloat) -> CGPoint {
        CADGeometry.offset(point, along: vector, by: distance)
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CADGeometry.midpoint(a, b)
    }

    private func reversed(_ vector: CGVector) -> CGVector {
        CADGeometry.reversed(vector)
    }

    private func readableLabelAngle(_ angle: Double) -> Double {
        CADGeometry.readableLabelAngle(angle)
    }

    private func rotatedRectBounds(center: CGPoint, size: CGSize, angleDegrees: Double) -> CGRect {
        CADGeometry.rotatedRectBounds(center: center, size: size, angleDegrees: angleDegrees)
    }

    private func rotatePoint(_ point: CGPoint, byDegrees degrees: Double, around center: CGPoint) -> CGPoint {
        CADGeometry.rotate(point, byDegrees: degrees, around: center)
    }

    private func angleDegrees(from center: CGPoint, to point: CGPoint) -> Double {
        CADGeometry.angleDegrees(from: center, to: point)
    }

    private func constrainedLineEnd(from start: CGPoint,
                                    to point: CGPoint,
                                    snapTo45Degrees: Bool) -> CGPoint {
        CADGeometry.constrainedLineEnd(from: start, to: point, snapTo45Degrees: snapTo45Degrees)
    }

    private func resizedBounds(for shape: CADShape,
                               handle: ResizeHandle,
                               to point: CGPoint,
                               preserveAspect: Bool) -> CGRect {
        let b = shape.bounds.standardized
        let angle = shape.rotationAngle
        let xAxis = rotatedUnitX(byDegrees: angle)
        let yAxis = rotatedUnitY(byDegrees: angle)
        let fixedPoint = rotatePoint(handle.opposite.point(in: b),
                                     byDegrees: angle,
                                     around: shape.center)
        let vector = CGVector(dx: point.x - fixedPoint.x,
                              dy: point.y - fixedPoint.y)
        let projectedX = dot(vector, xAxis)
        let projectedY = dot(vector, yAxis)
        let minSide = max(minimumResizeSide, 2 * invZoom)

        var width: CGFloat
        var height: CGFloat
        var xSign: CGFloat
        var ySign: CGFloat

        switch handle {
        case .topLeft:
            width = max(-projectedX, minSide)
            height = max(-projectedY, minSide)
            xSign = -1; ySign = -1
        case .top:
            width = b.width
            height = max(-projectedY, minSide)
            xSign = 0; ySign = -1
        case .topRight:
            width = max(projectedX, minSide)
            height = max(-projectedY, minSide)
            xSign = 1; ySign = -1
        case .right:
            width = max(projectedX, minSide)
            height = b.height
            xSign = 1; ySign = 0
        case .bottomRight:
            width = max(projectedX, minSide)
            height = max(projectedY, minSide)
            xSign = 1; ySign = 1
        case .bottom:
            width = b.width
            height = max(projectedY, minSide)
            xSign = 0; ySign = 1
        case .bottomLeft:
            width = max(-projectedX, minSide)
            height = max(projectedY, minSide)
            xSign = -1; ySign = 1
        case .left:
            width = max(-projectedX, minSide)
            height = b.height
            xSign = -1; ySign = 0
        }

        if preserveAspect {
            let aspect = max(b.width, minSide) / max(b.height, minSide)
            if handle.affectsX && !handle.affectsY {
                height = width / aspect
            } else if handle.affectsY && !handle.affectsX {
                width = height * aspect
            } else if width / max(height, minSide) > aspect {
                height = width / aspect
            } else {
                width = height * aspect
            }
        }

        let center = CGPoint(
            x: fixedPoint.x + xAxis.dx * width * xSign / 2 + yAxis.dx * height * ySign / 2,
            y: fixedPoint.y + xAxis.dy * width * xSign / 2 + yAxis.dy * height * ySign / 2
        )

        return CGRect(x: center.x - width / 2,
                      y: center.y - height / 2,
                      width: width,
                      height: height)
    }

    private func dot(_ a: CGVector, _ b: CGVector) -> CGFloat {
        CADGeometry.dot(a, b)
    }

    private func translatedShapes(from baseShapes: [UUID: CADShape], by delta: CGSize) -> [CADShape] {
        document.shapes.compactMap { shape in
            guard document.selectedIDs.contains(shape.id),
                  var base = baseShapes[shape.id] else { return nil }
            base.translate(by: delta)
            return base
        }
    }

    private func snapMovingShapes(_ movingShapes: [CADShape],
                                  excluding excludedIDs: Set<UUID>) -> SnapResult {
        snapper(excluding: excludedIDs).snap(movingShapes: movingShapes)
    }

    private func snappedPoint(_ point: CGPoint, excluding excludedIDs: Set<UUID>) -> (point: CGPoint, guides: [ConstructionGuide]) {
        snapper(excluding: excludedIDs).snap(point: point)
    }

    private func snapper(excluding excludedIDs: Set<UUID>) -> ConstructionSnapper {
        ConstructionSnapper(
            shapes: document.shapes,
            excludedIDs: excludedIDs,
            tolerance: snapToleranceScreen * invZoom,
            guidePadding: constructionGuidePadding * invZoom
        )
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
        var newBounds = shape.bounds
        switch axis {
        case .width:  newBounds.size.width  = CGFloat(px)
        case .height: newBounds.size.height = CGFloat(px)
        }
        shape.resize(to: newBounds)

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

        if document.currentTool == .pointSelect {
            handlePointSelectDown(pt: pt, event: event)
            return
        }

        // ── Resize handle hit test ─────────────────────────────────
        if document.currentTool == .select,
           let resizeTarget = resizeHandle(at: pt) {
            startResize(for: resizeTarget.shape, handle: resizeTarget.handle, at: pt)
            return
        }

        // ── Rotation handle hit test ────────────────────────────────
        for shape in document.shapes.reversed() where document.selectedIDs.contains(shape.id) {
            if let r = rotationHandleRects[shape.id] ?? rotationHandleHitRect(for: shape),
               r.contains(pt) {
                startRotation(for: shape, at: pt)
                return
            }
        }

        // ── Dimension label hit test (only visible dimension labels) ──
        if document.dimensionDisplayMode != .none {
            for shape in document.shapes.reversed() where shouldDrawDimensions(for: shape) {
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
        } else if document.currentTool.shapeType != nil {
            isDrawing = true
            drawStart = pt
            currentRect = .zero
            currentRotationAngle = 0
        }
    }

    override func mouseDragged(with event: NSEvent) {

        if isEditingPoint {
            let pt = convert(event.locationInWindow, from: nil)
            updatePointEdit(to: pt, event: event)
            return
        }

        if isEditingPoint {
            addCursorRect(bounds, cursor: .closedHand)
        } else if isResizing {
            let pt = convert(event.locationInWindow, from: nil)
            updateResize(to: pt, event: event)
            return
        }

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
            if isMarqueeSelecting {
                updateSelectionMarquee(to: pt)
            } else if isDragging, !document.selectedIDs.isEmpty {
                updateShapeDrag(to: pt, event: event)
            }
        } else if isDrawing, document.currentTool.shapeType != nil {
            if document.currentTool == .line {
                let end = constrainedLineEnd(from: drawStart,
                                             to: pt,
                                             snapTo45Degrees: event.modifierFlags.contains(.shift))
                let geometry = CADShape.lineGeometry(from: drawStart,
                                                     to: end,
                                                     strokeWidth: document.strokeWidth)
                currentRect = geometry.bounds
                currentRotationAngle = geometry.rotationAngle
            } else {
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
                currentRotationAngle = 0
            }
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isEditingPoint {
            finishPointEdit()
            return
        }

        if isResizing {
            finishResize()
            return
        }

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
            if isMarqueeSelecting {
                finishSelectionMarquee()
            } else {
                finishShapeDrag()
            }
        } else if isDrawing, document.currentTool.shapeType != nil {
            isDrawing = false
            if document.currentTool == .line, currentRect.width > 4 {
                let type = document.currentTool.shapeType!
                let shape = CADShape(type: type, bounds: currentRect,
                                     name: document.nextName(for: type),
                                     fillColor: document.fillColor,
                                     strokeColor: document.strokeColor,
                                     strokeWidth: document.strokeWidth,
                                     rotationAngle: currentRotationAngle)
                document.addShape(shape)
                document.selectShape(id: shape.id)
            } else if currentRect.width > 4, currentRect.height > 4 {
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
            currentRotationAngle = 0
            needsDisplay = true
        }
    }

    private func handleSelectDown(pt: CGPoint, event: NSEvent) {
        let hit = document.shapes.reversed().first { $0.contains(pt) }
        if let shape = hit {
            cancelSelectionMarquee()
            if !document.selectedIDs.contains(shape.id) {
                document.selectShape(id: shape.id, additive: event.modifierFlags.contains(.shift))
            }
            startShapeDrag(at: pt)
        } else {
            startSelectionMarquee(at: pt, additive: event.modifierFlags.contains(.shift))
        }
        needsDisplay = true
    }

    private func handlePointSelectDown(pt: CGPoint, event: NSEvent) {
        if dimensionEditor != nil { dismissDimensionEditor() }

        if let target = pointHandle(at: pt) {
            document.selectShape(id: target.shape.id)
            startPointEdit(shape: target.shape, pointIndex: target.pointIndex)
            return
        }

        if let shape = document.shapes.reversed().first(where: { $0.contains(pt) }) {
            document.selectShape(id: shape.id, additive: event.modifierFlags.contains(.shift))
        } else if !event.modifierFlags.contains(.shift) {
            document.deselectAll()
        }

        activeConstructionGuides = []
        needsDisplay = true
    }

    private func pointHandle(at point: CGPoint) -> (shape: CADShape, pointIndex: Int)? {
        for shape in document.shapes.reversed() {
            let points = shape.editablePoints()
            guard !points.isEmpty else { continue }

            for index in points.indices {
                let key = PointHandleKey(shapeID: shape.id, pointIndex: index)
                let rect = pointHandleRects[key] ?? pointHandleRect(centeredAt: points[index])
                if rect.contains(point) {
                    return (shape, index)
                }
            }
        }

        return nil
    }

    private func pointHandleRect(centeredAt point: CGPoint) -> CGRect {
        let hs = pointHandleSize * invZoom
        return CGRect(x: point.x - hs / 2,
                      y: point.y - hs / 2,
                      width: hs,
                      height: hs)
            .insetBy(dx: -6 * invZoom, dy: -6 * invZoom)
    }

    private func startPointEdit(shape: CADShape, pointIndex: Int) {
        isEditingPoint = true
        pointEditTarget = PointEditTarget(shapeID: shape.id, pointIndex: pointIndex)
        activeConstructionGuides = []
        document.beginPointEdit()
        NSCursor.closedHand.set()
    }

    private func updatePointEdit(to point: CGPoint, event: NSEvent) {
        guard let target = pointEditTarget,
              let shape = document.shapes.first(where: { $0.id == target.shapeID })
        else { return }

        let snap = event.modifierFlags.contains(.option)
            ? (point: point, guides: [])
            : snappedPoint(point, excluding: [target.shapeID])

        guard let updated = shape.movingEditablePoint(at: target.pointIndex, to: snap.point) else { return }
        document.replaceShapeDuringPointEdit(updated)
        activeConstructionGuides = snap.guides
        needsDisplay = true
    }

    private func finishPointEdit() {
        document.commitPointEdit()
        isEditingPoint = false
        pointEditTarget = nil
        activeConstructionGuides = []
        window?.resetCursorRects()
        needsDisplay = true
    }

    private func startSelectionMarquee(at point: CGPoint, additive: Bool) {
        isDragging = false
        activeConstructionGuides = []
        marqueeStart = point
        marqueeRect = CGRect(origin: point, size: .zero)
        marqueeBaseSelection = document.selectedIDs
        marqueeAddsToSelection = additive
        isMarqueeSelecting = true
        if !additive { document.deselectAll() }
    }

    private func updateSelectionMarquee(to point: CGPoint) {
        marqueeRect = CGRect(
            x: min(marqueeStart.x, point.x),
            y: min(marqueeStart.y, point.y),
            width: abs(point.x - marqueeStart.x),
            height: abs(point.y - marqueeStart.y)
        )
        needsDisplay = true
    }

    private func finishSelectionMarquee() {
        defer {
            isMarqueeSelecting = false
            marqueeRect = .zero
            marqueeBaseSelection = []
            marqueeAddsToSelection = false
            needsDisplay = true
        }

        guard marqueeRect.width > 4 * invZoom, marqueeRect.height > 4 * invZoom else {
            if marqueeAddsToSelection { document.selectedIDs = marqueeBaseSelection }
            return
        }

        let rect = marqueeRect.standardized
        let selected = Set(document.shapes.compactMap { shape in
            shape.visualBounds.standardized.intersects(rect) ? shape.id : nil
        })
        document.selectedIDs = marqueeAddsToSelection ? marqueeBaseSelection.union(selected) : selected
    }

    private func cancelSelectionMarquee() {
        isMarqueeSelecting = false
        marqueeRect = .zero
        marqueeBaseSelection = []
        marqueeAddsToSelection = false
        activeConstructionGuides = []
    }

    private func startShapeDrag(at point: CGPoint) {
        isDragging = true
        lastDragPt = point
        dragStartPt = point
        dragBaseShapes = Dictionary(uniqueKeysWithValues: document.shapes
            .filter { document.selectedIDs.contains($0.id) }
            .map { ($0.id, $0) })
        activeConstructionGuides = []
        document.beginMove()
    }

    private func updateShapeDrag(to point: CGPoint, event: NSEvent) {
        let rawDelta = CGSize(width: point.x - dragStartPt.x,
                              height: point.y - dragStartPt.y)
        let proposedShapes = translatedShapes(from: dragBaseShapes, by: rawDelta)
        let snap = event.modifierFlags.contains(.option)
            ? SnapResult(delta: .zero, guides: [])
            : snapMovingShapes(proposedShapes, excluding: document.selectedIDs)
        let finalDelta = CGSize(width: rawDelta.width + snap.delta.width,
                                height: rawDelta.height + snap.delta.height)

        document.moveSelectedShapes(from: dragBaseShapes, by: finalDelta)
        activeConstructionGuides = snap.guides
        lastDragPt = point
        needsDisplay = true
    }

    private func finishShapeDrag() {
        document.commitMove()
        isDragging = false
        dragBaseShapes.removeAll()
        activeConstructionGuides = []
        needsDisplay = true
    }

    private func resizeHandle(at point: CGPoint) -> (shape: CADShape, handle: ResizeHandle)? {
        for shape in document.shapes.reversed() where document.selectedIDs.contains(shape.id) {
            let rects = resizeHandleRects[shape.id] ?? calculatedResizeHandleRects(for: shape)
            for handle in ResizeHandle.allCases {
                if rects[handle]?.contains(point) == true {
                    return (shape, handle)
                }
            }
        }
        return nil
    }

    private func startResize(for shape: CADShape, handle: ResizeHandle, at point: CGPoint) {
        if dimensionEditor != nil { dismissDimensionEditor() }

        isResizing = true
        resizingShapeID = shape.id
        resizingHandle = handle
        resizeStartShape = shape
        activeConstructionGuides = []
        document.beginResize()
        resizeCursor(for: shape, handle: handle).set()
    }

    private func updateResize(to point: CGPoint, event: NSEvent) {
        guard let id = resizingShapeID,
              let handle = resizingHandle,
              let startShape = resizeStartShape else { return }

        let snap = event.modifierFlags.contains(.option)
            ? (point: point, guides: [])
            : snappedPoint(point, excluding: [id])
        let resized = resizedBounds(for: startShape,
                                    handle: handle,
                                    to: snap.point,
                                    preserveAspect: event.modifierFlags.contains(.shift))

        document.resizeShape(id: id, to: resized)
        activeConstructionGuides = snap.guides
        needsDisplay = true
    }

    private func finishResize() {
        document.commitResize()
        isResizing = false
        resizingShapeID = nil
        resizingHandle = nil
        resizeStartShape = nil
        activeConstructionGuides = []
        window?.resetCursorRects()
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

    private func resizeCursor(for shape: CADShape, handle: ResizeHandle) -> NSCursor {
        let angle = CADShape.normalizedRotation(shape.rotationAngle + handle.cursorAngleOffset)
        return Self.resizeCursor(angleDegrees: angle)
    }

    private static func resizeCursor(angleDegrees: Double) -> NSCursor {
        let normalized = CADShape.normalizedRotation(angleDegrees)
        let cacheKey = Int(round(normalized))
        if let cursor = resizeCursorCache[cacheKey] { return cursor }

        let size = CGSize(width: 32, height: 32)
        let image = NSImage(size: size)
        image.lockFocus()

        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: CGFloat(normalized * Double.pi / 180))

            func strokeArrow(color: NSColor, lineWidth: CGFloat) {
                ctx.setStrokeColor(color.cgColor)
                ctx.setLineWidth(lineWidth)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: -10, y: 0))
                ctx.addLine(to: CGPoint(x: 10, y: 0))
                ctx.move(to: CGPoint(x: 5, y: -5))
                ctx.addLine(to: CGPoint(x: 10, y: 0))
                ctx.addLine(to: CGPoint(x: 5, y: 5))
                ctx.move(to: CGPoint(x: -5, y: -5))
                ctx.addLine(to: CGPoint(x: -10, y: 0))
                ctx.addLine(to: CGPoint(x: -5, y: 5))
                ctx.strokePath()
            }

            strokeArrow(color: .white, lineWidth: 5)
            strokeArrow(color: .black, lineWidth: 2.2)
        }

        image.unlockFocus()

        let cursor = NSCursor(image: image, hotSpot: CGPoint(x: size.width / 2, y: size.height / 2))
        resizeCursorCache[cacheKey] = cursor
        return cursor
    }

    override func resetCursorRects() {
        if isResizing {
            if let id = resizingShapeID,
               let handle = resizingHandle,
               let shape = document.shapes.first(where: { $0.id == id }) {
                addCursorRect(bounds, cursor: resizeCursor(for: shape, handle: handle))
            } else {
                addCursorRect(bounds, cursor: .crosshair)
            }
        } else if isPanning {
            addCursorRect(bounds, cursor: .closedHand)
        } else if isSpaceDown {
            addCursorRect(bounds, cursor: .openHand)
        } else {
            addCursorRect(bounds, cursor: document.currentTool.shapeType == nil ? .arrow : .crosshair)
            if document.currentTool == .select {
                for shape in document.shapes where document.selectedIDs.contains(shape.id) {
                    let rects = resizeHandleRects[shape.id] ?? calculatedResizeHandleRects(for: shape)
                    for handle in ResizeHandle.allCases {
                        if let rect = rects[handle] {
                            addCursorRect(rect, cursor: resizeCursor(for: shape, handle: handle))
                        }
                    }
                }
                for shape in document.shapes where document.selectedIDs.contains(shape.id) {
                    if let rect = rotationHandleRects[shape.id] ?? rotationHandleHitRect(for: shape) {
                        addCursorRect(rect, cursor: .openHand)
                    }
                }
            } else if document.currentTool == .pointSelect {
                for shape in document.shapes where document.selectedIDs.contains(shape.id) {
                    let points = shape.editablePoints()
                    for index in points.indices {
                        let key = PointHandleKey(shapeID: shape.id, pointIndex: index)
                        let rect = pointHandleRects[key] ?? pointHandleRect(centeredAt: points[index])
                        addCursorRect(rect, cursor: .openHand)
                    }
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
