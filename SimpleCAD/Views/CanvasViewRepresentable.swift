import SwiftUI
import AppKit
import Combine

struct CanvasScrollRepresentable: NSViewRepresentable {
    @EnvironmentObject var document: CADDocument

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers    = true
        scrollView.backgroundColor       = NSColor.underPageBackgroundColor
        scrollView.borderType            = .noBorder

        // Zoom natif NSScrollView
        scrollView.allowsMagnification = true
        scrollView.minMagnification    = 0.05
        scrollView.maxMagnification    = 16.0
        scrollView.magnification       = document.zoomLevel
        scrollView.contentView.postsBoundsChangedNotifications = true

        let canvas = CADCanvasView()
        canvas.document = document
        canvas.frame = NSRect(origin: .zero, size: document.canvasSize)
        scrollView.backgroundColor = canvas.surroundingBackgroundColor
        context.coordinator.canvasView = canvas
        context.coordinator.scrollView = scrollView
        context.coordinator.document   = document

        scrollView.documentView = canvas

        // Réagir aux changements du document → redessiner
        let coordinator = context.coordinator
        coordinator.cancellable = document.objectWillChange.sink { [weak canvas, weak coordinator] _ in
            DispatchQueue.main.async {
                canvas?.frame = NSRect(origin: .zero, size: document.canvasSize)
                canvas?.needsDisplay = true
                coordinator?.invalidateCanvas()
            }
        }

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollBoundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        // Observer la magnification de l'utilisateur (pinch)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.magnificationChanged(_:)),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )

        // Centrer au premier affichage
        DispatchQueue.main.async {
            if let bounds = document.zoomToFitBounds {
                document.zoomToFitBounds = nil
                document.scrollTarget = nil
                context.coordinator.zoomToFit(bounds)
            } else {
                let target = document.scrollTarget
                    ?? CGPoint(x: document.canvasSize.width  / 2,
                               y: document.canvasSize.height / 2)
                context.coordinator.scroll(to: target)
                document.scrollTarget = nil
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let canvas = context.coordinator.canvasView else { return }
        canvas.document = document
        canvas.frame = NSRect(origin: .zero, size: document.canvasSize)
        canvas.updateAppearanceColors()
        canvas.resetCursorRects()
        canvas.needsDisplay = true

        // Synchroniser le zoom si changé depuis l'extérieur (bouton / raccourci)
        let coord = context.coordinator
        if !coord.isUpdatingFromScrollView,
           abs(scrollView.magnification - document.zoomLevel) > 0.001 {
            coord.lastAppliedZoom = document.zoomLevel
            let clip   = scrollView.contentView.bounds
            let center = CGPoint(x: clip.midX, y: clip.midY)
            scrollView.setMagnification(document.zoomLevel, centeredAt: center)
            coord.invalidateCanvas()
        }

        // Consommer zoomToFitBounds en priorité : il ajuste le zoom puis centre la vue.
        if let bounds = document.zoomToFitBounds {
            DispatchQueue.main.async {
                document.zoomToFitBounds = nil
                document.scrollTarget = nil
                context.coordinator.zoomToFit(bounds)
            }
        } else if let target = document.scrollTarget {
            DispatchQueue.main.async {
                context.coordinator.scroll(to: target)
                document.scrollTarget = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        var canvasView:  CADCanvasView?
        var scrollView:  NSScrollView?
        var cancellable: AnyCancellable?
        weak var document: CADDocument?

        var lastAppliedZoom:       Double = 1.0
        var isUpdatingFromScrollView = false

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func invalidateCanvas() {
            canvasView?.needsDisplay = true
        }

        func zoomToFit(_ rect: CGRect) {
            guard let sv = scrollView,
                  let doc = document else { return }

            let viewport = sv.contentView.frame.size
            guard viewport.width > 0, viewport.height > 0 else {
                scroll(to: CGPoint(x: rect.midX, y: rect.midY))
                return
            }

            let padding = max(max(rect.width, rect.height) * 0.08, 80)
            let paddedWidth = max(rect.width + padding * 2, 1)
            let paddedHeight = max(rect.height + padding * 2, 1)
            let zoom = min(
                sv.maxMagnification,
                max(sv.minMagnification, Double(min(viewport.width / paddedWidth,
                                                    viewport.height / paddedHeight)))
            )

            lastAppliedZoom = zoom
            isUpdatingFromScrollView = true
            let center = CGPoint(x: rect.midX, y: rect.midY)
            sv.setMagnification(zoom, centeredAt: center)
            doc.zoomLevel = zoom
            scroll(to: center)
            invalidateCanvas()

            DispatchQueue.main.async { [weak self] in
                self?.isUpdatingFromScrollView = false
            }
        }

        func scroll(to point: CGPoint) {
            guard let sv = scrollView else { return }
            let clip = sv.contentView
            let visibleSize = clip.documentVisibleRect.size
            let targetRect = NSRect(
                x: point.x - visibleSize.width / 2,
                y: point.y - visibleSize.height / 2,
                width: visibleSize.width,
                height: visibleSize.height
            )
            let constrained = clip.constrainBoundsRect(targetRect)
            clip.scroll(to: constrained.origin)
            sv.reflectScrolledClipView(clip)
            invalidateCanvas()
        }

        @objc func magnificationChanged(_ notification: Notification) {
            guard let sv = scrollView,
                  let doc = document else { return }
            let zoom = sv.magnification
            lastAppliedZoom          = zoom
            isUpdatingFromScrollView = true
            DispatchQueue.main.async { [weak self] in
                doc.zoomLevel = zoom
                self?.isUpdatingFromScrollView = false
                self?.invalidateCanvas()
            }
        }

        @objc func scrollBoundsChanged(_ notification: Notification) {
            invalidateCanvas()
        }
    }
}
