import AppKit

// MARK: - Construction guides

enum GuideOrientation {
    case vertical
    case horizontal
}

struct ConstructionGuide {
    var orientation: GuideOrientation
    var position: CGFloat
    var start: CGFloat
    var end: CGFloat
}

struct SnapResult {
    var delta: CGSize
    var guides: [ConstructionGuide]
}

private struct SnapAnchor {
    var value: CGFloat
    var bounds: CGRect
}

// MARK: - ConstructionSnapper

struct ConstructionSnapper {
    var shapes: [CADShape]
    var excludedIDs: Set<UUID>
    var tolerance: CGFloat
    var guidePadding: CGFloat

    func snap(movingShapes: [CADShape]) -> SnapResult {
        let references = referenceAnchors()
        guard !references.vertical.isEmpty || !references.horizontal.isEmpty else {
            return SnapResult(delta: .zero, guides: [])
        }

        let moving = anchors(for: movingShapes)
        var guides: [ConstructionGuide] = []
        var delta = CGSize.zero

        if let match = bestSnapMatch(moving: moving.vertical,
                                     references: references.vertical,
                                     orientation: .vertical) {
            delta.width = match.adjustment
            guides.append(match.guide)
        }

        if let match = bestSnapMatch(moving: moving.horizontal,
                                     references: references.horizontal,
                                     orientation: .horizontal) {
            delta.height = match.adjustment
            guides.append(match.guide)
        }

        return SnapResult(delta: delta, guides: guides)
    }

    func snap(point: CGPoint) -> (point: CGPoint, guides: [ConstructionGuide]) {
        let references = referenceAnchors()
        let pointBounds = CGRect(x: point.x, y: point.y, width: 0, height: 0)
        let verticalAnchor = [SnapAnchor(value: point.x, bounds: pointBounds)]
        let horizontalAnchor = [SnapAnchor(value: point.y, bounds: pointBounds)]

        var snapped = point
        var guides: [ConstructionGuide] = []

        if let match = bestSnapMatch(moving: verticalAnchor,
                                     references: references.vertical,
                                     orientation: .vertical) {
            snapped.x += match.adjustment
            guides.append(match.guide)
        }

        if let match = bestSnapMatch(moving: horizontalAnchor,
                                     references: references.horizontal,
                                     orientation: .horizontal) {
            snapped.y += match.adjustment
            guides.append(match.guide)
        }

        return (snapped, guides)
    }

    private func referenceAnchors() -> (vertical: [SnapAnchor], horizontal: [SnapAnchor]) {
        anchors(for: shapes.filter { !excludedIDs.contains($0.id) })
    }

    private func anchors(for shapes: [CADShape]) -> (vertical: [SnapAnchor], horizontal: [SnapAnchor]) {
        var vertical: [SnapAnchor] = []
        var horizontal: [SnapAnchor] = []

        for shape in shapes {
            let bounds = shape.visualBounds.standardized
            let points = shape.rotatedHandlePoints + [shape.center]
            vertical.append(contentsOf: points.map { SnapAnchor(value: $0.x, bounds: bounds) })
            horizontal.append(contentsOf: points.map { SnapAnchor(value: $0.y, bounds: bounds) })
        }

        return (vertical, horizontal)
    }

    private func bestSnapMatch(moving: [SnapAnchor],
                               references: [SnapAnchor],
                               orientation: GuideOrientation) -> (adjustment: CGFloat, guide: ConstructionGuide)? {
        var best: (distance: CGFloat, adjustment: CGFloat, guide: ConstructionGuide)?

        for movingAnchor in moving {
            for reference in references {
                let adjustment = reference.value - movingAnchor.value
                let distance = abs(adjustment)
                guard distance <= tolerance else { continue }

                let guide: ConstructionGuide
                switch orientation {
                case .vertical:
                    let start = min(movingAnchor.bounds.minY, reference.bounds.minY) - guidePadding
                    let end = max(movingAnchor.bounds.maxY, reference.bounds.maxY) + guidePadding
                    guide = ConstructionGuide(orientation: .vertical,
                                              position: reference.value,
                                              start: start,
                                              end: end)
                case .horizontal:
                    let start = min(movingAnchor.bounds.minX, reference.bounds.minX) - guidePadding
                    let end = max(movingAnchor.bounds.maxX, reference.bounds.maxX) + guidePadding
                    guide = ConstructionGuide(orientation: .horizontal,
                                              position: reference.value,
                                              start: start,
                                              end: end)
                }

                if best == nil || distance < best!.distance {
                    best = (distance, adjustment, guide)
                }
            }
        }

        guard let best else { return nil }
        return (adjustment: best.adjustment, guide: best.guide)
    }
}
