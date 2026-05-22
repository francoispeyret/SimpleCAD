import AppKit

// MARK: - DocumentLayoutService

enum DocumentLayoutService {
    static func boundingRect(for shapes: [CADShape]) -> CGRect? {
        guard var bounds = shapes.first?.visualBounds.standardized else { return nil }
        for shape in shapes.dropFirst() {
            bounds = bounds.union(shape.visualBounds.standardized)
        }
        return bounds
    }

    static func centerLoadedContent(_ loadedShapes: [CADShape],
                                    in loadedCanvasSize: CGSize,
                                    defaultCanvasSize: CGSize,
                                    margin: CGFloat) -> (shapes: [CADShape], bounds: CGRect?, canvasSize: CGSize) {
        guard let contentBounds = boundingRect(for: loadedShapes) else {
            let canvasSize = CGSize(width: max(defaultCanvasSize.width, loadedCanvasSize.width),
                                    height: max(defaultCanvasSize.height, loadedCanvasSize.height))
            return (loadedShapes, nil, canvasSize)
        }

        let canvasSize = CGSize(
            width: max(defaultCanvasSize.width,
                       loadedCanvasSize.width,
                       contentBounds.width + margin * 2),
            height: max(defaultCanvasSize.height,
                        loadedCanvasSize.height,
                        contentBounds.height + margin * 2)
        )
        let targetCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let delta = CGSize(width: targetCenter.x - contentBounds.midX,
                           height: targetCenter.y - contentBounds.midY)

        let centeredShapes = loadedShapes.map { shape in
            var adjusted = shape
            adjusted.translate(by: delta)
            return adjusted
        }

        return (
            centeredShapes,
            contentBounds.offsetBy(dx: delta.width, dy: delta.height),
            canvasSize
        )
    }
}
