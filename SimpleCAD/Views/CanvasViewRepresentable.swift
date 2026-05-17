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

        let canvas = CADCanvasView()
        canvas.document = document
        canvas.frame = NSRect(origin: .zero, size: document.canvasSize)
        context.coordinator.canvasView  = canvas
        context.coordinator.scrollView  = scrollView

        scrollView.documentView = canvas

        // Observer les changements du document → redessiner le canvas
        context.coordinator.cancellable = document.objectWillChange.sink { [weak canvas, weak scrollView] _ in
            DispatchQueue.main.async {
                canvas?.frame = NSRect(origin: .zero, size: document.canvasSize)
                canvas?.needsDisplay = true
            }
        }

        // Centrer la vue sur le canvas au premier affichage
        DispatchQueue.main.async {
            let target = document.scrollTarget
                ?? CGPoint(x: document.canvasSize.width / 2,
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

        // Consommer la demande de centrage (nouveau doc ou fichier ouvert)
        if let target = document.scrollTarget {
            DispatchQueue.main.async {
                context.coordinator.scroll(to: target)
                document.scrollTarget = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    class Coordinator {
        var canvasView: CADCanvasView?
        var scrollView: NSScrollView?
        var cancellable: AnyCancellable?

        /// Fait défiler le scrollView pour centrer la vue sur `point` (coord. canvas).
        func scroll(to point: CGPoint) {
            guard let sv = scrollView else { return }
            let vis = sv.contentView.bounds.size
            let x = max(0, point.x - vis.width  / 2)
            let y = max(0, point.y - vis.height / 2)
            sv.contentView.scroll(to: CGPoint(x: x, y: y))
            sv.reflectScrolledClipView(sv.contentView)
        }
    }
}
