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

        let canvas = CADCanvasView()
        canvas.document = document
        canvas.frame = NSRect(origin: .zero, size: document.canvasSize)
        context.coordinator.canvasView = canvas
        context.coordinator.scrollView = scrollView
        context.coordinator.document   = document

        scrollView.documentView = canvas

        // Réagir aux changements du document → redessiner
        context.coordinator.cancellable = document.objectWillChange.sink { [weak canvas] _ in
            DispatchQueue.main.async {
                canvas?.frame = NSRect(origin: .zero, size: document.canvasSize)
                canvas?.needsDisplay = true
            }
        }

        // Observer la magnification de l'utilisateur (pinch)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.magnificationChanged(_:)),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )

        // Centrer au premier affichage
        DispatchQueue.main.async {
            let target = document.scrollTarget
                ?? CGPoint(x: document.canvasSize.width  / 2,
                           y: document.canvasSize.height / 2)
            context.coordinator.scroll(to: target)
            document.scrollTarget = nil
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let canvas = context.coordinator.canvasView else { return }
        canvas.document = document
        canvas.frame = NSRect(origin: .zero, size: document.canvasSize)
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
        }

        // Consommer scrollTarget
        if let target = document.scrollTarget {
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

        func scroll(to point: CGPoint) {
            guard let sv = scrollView else { return }
            let vis = sv.contentView.bounds.size
            let x = max(0, point.x * sv.magnification - vis.width  / 2)
            let y = max(0, point.y * sv.magnification - vis.height / 2)
            sv.contentView.scroll(to: CGPoint(x: x, y: y))
            sv.reflectScrolledClipView(sv.contentView)
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
            }
        }
    }
}
