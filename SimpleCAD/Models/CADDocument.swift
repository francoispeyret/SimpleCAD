import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - HistoryEntry

struct HistoryEntry: Identifiable {
    let id    = UUID()
    let label: String
    let shapes: [CADShape]
}

// MARK: - CADDocument

class CADDocument: ObservableObject {

    // MARK: - State

    @Published var shapes:           [CADShape]  = []
    @Published var selectedIDs:      Set<UUID>   = []
    @Published var currentTool:      Tool        = .select
    @Published var fillColor:        CADColor    = .white
    @Published var strokeColor:      CADColor    = .black
    @Published var strokeWidth:      Double      = 2.0
    static let defaultCanvasSize = CGSize(width: 32_000, height: 32_000)

    @Published var canvasSize:       CGSize      = CADDocument.defaultCanvasSize
    @Published var showGrid:         Bool        = true
    @Published var showDimensions:   Bool        = true
    @Published var unit:             DocumentUnit = .mm
    @Published var isDirty:          Bool        = false
    @Published var zoomLevel:        Double      = 1.0

    @Published var scrollTarget: CGPoint? = CGPoint(
        x: CADDocument.defaultCanvasSize.width  / 2,
        y: CADDocument.defaultCanvasSize.height / 2
    )
    @Published var zoomToFitBounds: CGRect? = nil

    // MARK: - History

    @Published private(set) var historyEntries: [HistoryEntry] = []
    @Published private(set) var historyIndex:   Int = 0

    private var preMoveShapes: [CADShape]? = nil
    private var preRotationShapes: [CADShape]? = nil
    private let importContentMargin: CGFloat = 400

    var canUndo: Bool { historyIndex > 0 }
    var canRedo: Bool { historyIndex < historyEntries.count - 1 }

    // MARK: - Other state

    var currentFileURL: URL?
    private var counters: [ShapeType: Int] = [:]

    // MARK: - Init

    init() {
        historyEntries = [HistoryEntry(label: "Nouveau document", shapes: [])]
        historyIndex   = 0
    }

    // MARK: - Derived

    var selectedShapes: [CADShape] { shapes.filter { selectedIDs.contains($0.id) } }

    // MARK: - Naming

    func nextName(for type: ShapeType) -> String {
        let n = (counters[type] ?? 0) + 1
        counters[type] = n
        return "\(type.rawValue) \(n)"
    }

    // MARK: - History engine

    /// Enregistre l'état courant de `shapes` dans l'historique avec un libellé.
    /// Doit être appelé APRÈS la modification.
    func recordAction(_ label: String) {
        // Tronquer la branche redo
        if historyIndex < historyEntries.count - 1 {
            historyEntries = Array(historyEntries.prefix(historyIndex + 1))
        }
        historyEntries.append(HistoryEntry(label: label, shapes: shapes))
        historyIndex = historyEntries.count - 1
        // Garder 50 opérations + l'état initial = 51 entrées max
        if historyEntries.count > 51 {
            historyEntries.removeFirst()
            historyIndex = historyEntries.count - 1
        }
        isDirty = true
    }

    /// Restaure l'état à un index quelconque de l'historique.
    func jumpToHistory(index: Int) {
        guard index >= 0, index < historyEntries.count, index != historyIndex else { return }
        historyIndex = index
        shapes       = historyEntries[historyIndex].shapes
        selectedIDs  = selectedIDs.filter { id in shapes.contains(where: { $0.id == id }) }
        isDirty      = historyIndex > 0
    }

    func undo() {
        guard canUndo else { return }
        jumpToHistory(index: historyIndex - 1)
    }

    func redo() {
        guard canRedo else { return }
        jumpToHistory(index: historyIndex + 1)
    }

    // MARK: - Zoom

    func zoomIn()    { zoomLevel = min(zoomLevel * 1.25, 16.0) }
    func zoomOut()   { zoomLevel = max(zoomLevel / 1.25, 0.05) }
    func resetZoom() { zoomLevel = 1.0 }

    // MARK: - Move tracking (canvas drag + touches fléchées)

    /// Appelé avant qu'un glisser commence. Idempotent.
    func beginMove() {
        if preMoveShapes == nil { preMoveShapes = shapes }
    }

    /// Appelé à la fin d'un glisser : enregistre "Déplacement" si les formes ont bougé.
    func commitMove() {
        guard let pre = preMoveShapes else { return }
        preMoveShapes = nil
        let moved = selectedIDs.contains { id in
            guard let old = pre.first(where: { $0.id == id }),
                  let new = shapes.first(where: { $0.id == id })
            else { return false }
            return old.bounds != new.bounds
        }
        if moved { recordAction("Déplacement") }
    }

    func beginRotation() {
        if preRotationShapes == nil { preRotationShapes = shapes }
    }

    func rotateShape(id: UUID, to angle: Double) {
        guard let i = shapes.firstIndex(where: { $0.id == id }) else { return }
        shapes[i].rotationAngle = CADShape.normalizedRotation(angle)
        isDirty = true
    }

    func commitRotation() {
        guard let pre = preRotationShapes else { return }
        preRotationShapes = nil
        let rotated = shapes.contains { shape in
            guard let old = pre.first(where: { $0.id == shape.id }) else { return false }
            return old.rotationAngle != shape.rotationAngle
        }
        if rotated { recordAction("Rotation") }
    }

    // MARK: - Shape operations

    func addShape(_ shape: CADShape) {
        shapes.append(shape)
        recordAction("Ajout \(shape.type.rawValue.lowercased())")
    }

    func updateShape(_ shape: CADShape) {
        guard let i = shapes.firstIndex(where: { $0.id == shape.id }) else { return }
        var updated = shape
        updated.rotationAngle = CADShape.normalizedRotation(updated.rotationAngle)
        shapes[i] = updated
        recordAction("Redimensionnement")
    }

    func removeSelected() {
        guard !selectedIDs.isEmpty else { return }
        let n = selectedIDs.count
        shapes.removeAll { selectedIDs.contains($0.id) }
        selectedIDs.removeAll()
        recordAction(n == 1 ? "Suppression" : "Suppression (\(n))")
    }

    func moveSelectedShapes(by delta: CGSize) {
        for id in selectedIDs {
            guard let i = shapes.firstIndex(where: { $0.id == id }) else { continue }
            shapes[i].bounds.origin.x += delta.width
            shapes[i].bounds.origin.y += delta.height
        }
        isDirty = true
        // Pas de recordAction ici : géré par beginMove/commitMove
    }

    func renameShape(id: UUID, to newName: String) {
        guard let i = shapes.firstIndex(where: { $0.id == id }) else { return }
        shapes[i].name = newName
        recordAction("Renommage")
    }

    // MARK: - Selection

    func selectShape(id: UUID, additive: Bool = false) {
        if additive { selectedIDs.insert(id) }
        else { selectedIDs = [id] }
    }

    func deselectAll() { selectedIDs.removeAll() }
    func selectAll()   { selectedIDs = Set(shapes.map(\.id)) }

    func bringToFront() {
        guard let id = selectedIDs.first,
              let i = shapes.firstIndex(where: { $0.id == id }) else { return }
        let shape = shapes.remove(at: i)
        shapes.append(shape)
        recordAction("Premier plan")
    }

    func sendToBack() {
        guard let id = selectedIDs.first,
              let i = shapes.firstIndex(where: { $0.id == id }) else { return }
        let shape = shapes.remove(at: i)
        shapes.insert(shape, at: 0)
        recordAction("Arrière-plan")
    }

    // MARK: - Apply style to selection

    func applyFillToSelection() {
        guard !selectedIDs.isEmpty else { return }
        for id in selectedIDs {
            guard let i = shapes.firstIndex(where: { $0.id == id }) else { continue }
            shapes[i].fillColor = fillColor
        }
        recordAction("Remplissage")
    }

    func applyStrokeToSelection() {
        guard !selectedIDs.isEmpty else { return }
        for id in selectedIDs {
            guard let i = shapes.firstIndex(where: { $0.id == id }) else { continue }
            shapes[i].strokeColor = strokeColor
        }
        recordAction("Contour")
    }

    func applyStrokeWidthToSelection() {
        guard !selectedIDs.isEmpty else { return }
        for id in selectedIDs {
            guard let i = shapes.firstIndex(where: { $0.id == id }) else { continue }
            shapes[i].strokeWidth = strokeWidth
        }
        recordAction("Épaisseur")
    }

    // MARK: - File operations

    func new() {
        shapes = []; selectedIDs = []; counters = [:]; currentFileURL = nil
        canvasSize = Self.defaultCanvasSize
        isDirty    = false
        historyEntries = [HistoryEntry(label: "Nouveau document", shapes: [])]
        historyIndex   = 0
        scrollTarget = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        zoomToFitBounds = nil
    }

    func save() {
        if let url = currentFileURL { writeToURL(url) }
        else { saveAs() }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .data]
        panel.nameFieldStringValue = "Plan sans titre.svg"
        panel.prompt = "Enregistrer"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        currentFileURL = url
        writeToURL(url)
    }

    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .data]
        panel.prompt = "Ouvrir"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try SVGService.load(from: url)
            applyLoadResult(result, url: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func open(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let result = try SVGService.load(from: url)
            DispatchQueue.main.async { [weak self] in
                self?.applyLoadResult(result, url: url)
            }
        } catch { }
    }

    private func applyLoadResult(_ result: SVGLoadResult, url: URL) {
        let centeredContent = centerLoadedContent(result.shapes, in: result.canvasSize)

        shapes = centeredContent.shapes
        counters = result.counters
        canvasSize = centeredContent.canvasSize
        unit = result.unit
        currentFileURL = url
        selectedIDs = []
        isDirty = false
        historyEntries = [HistoryEntry(label: "Ouverture fichier", shapes: shapes)]
        historyIndex   = 0
        scrollTarget = centeredContent.bounds.map { CGPoint(x: $0.midX, y: $0.midY) }
            ?? CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        zoomToFitBounds = centeredContent.bounds
    }

    private func centerLoadedContent(_ loadedShapes: [CADShape], in loadedCanvasSize: CGSize) -> (shapes: [CADShape], bounds: CGRect?, canvasSize: CGSize) {
        guard let contentBounds = boundingRect(for: loadedShapes) else {
            return (loadedShapes, nil, loadedCanvasSize)
        }

        let canvasSize = CGSize(
            width: max(loadedCanvasSize.width, contentBounds.width + importContentMargin * 2),
            height: max(loadedCanvasSize.height, contentBounds.height + importContentMargin * 2)
        )
        let targetCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let delta = CGSize(width: targetCenter.x - contentBounds.midX,
                           height: targetCenter.y - contentBounds.midY)

        let centeredShapes = loadedShapes.map { shape in
            var adjusted = shape
            adjusted.bounds = adjusted.bounds.offsetBy(dx: delta.width, dy: delta.height)
            return adjusted
        }

        return (
            centeredShapes,
            contentBounds.offsetBy(dx: delta.width, dy: delta.height),
            canvasSize
        )
    }

    private func boundingRect(for shapes: [CADShape]) -> CGRect? {
        guard var bounds = shapes.first?.visualBounds.standardized else { return nil }
        for shape in shapes.dropFirst() {
            bounds = bounds.union(shape.visualBounds.standardized)
        }
        return bounds
    }

    func moveShapesReversed(from source: IndexSet, to destination: Int) {
        let n = shapes.count
        let originalSource = IndexSet(source.map { n - 1 - $0 })
        let originalDest   = max(0, min(n, n - destination))
        shapes.move(fromOffsets: originalSource, toOffset: originalDest)
        recordAction("Réorganisation calques")
    }

    private func writeToURL(_ url: URL) {
        do {
            try SVGService.save(document: self, to: url)
            isDirty = false
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
