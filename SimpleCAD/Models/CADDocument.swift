import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - CADDocument

class CADDocument: ObservableObject {
    // MARK: - State

    @Published var shapes:           [CADShape]  = []
    @Published var selectedIDs:      Set<UUID>   = []
    @Published var currentTool:      Tool        = .select
    @Published var fillColor:        CADColor    = .white
    @Published var strokeColor:      CADColor    = .black
    @Published var strokeWidth:      Double      = 2.0
    static let defaultCanvasSize = CGSize(width: 16_000, height: 16_000)

    @Published var canvasSize:       CGSize      = CADDocument.defaultCanvasSize
    @Published var gridDisplayMode:  GridDisplayMode = .standard
    @Published var dimensionDisplayMode: DimensionDisplayMode = .selected
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
    private var historyStore = CADHistoryStore()

    private var preMoveShapes: [CADShape]? = nil
    private var preRotationShapes: [CADShape]? = nil
    private var preResizeShapes: [CADShape]? = nil
    private var prePointEditShapes: [CADShape]? = nil
    private let importContentMargin: CGFloat = 400

    var canUndo: Bool { historyIndex > 0 }
    var canRedo: Bool { historyIndex < historyEntries.count - 1 }

    // MARK: - Other state

    @Published var currentFileURL: URL?
    @Published private(set) var recentFileURLs: [URL] = []
    private var recentFileStore = RecentFileStore()
    private var counters: [ShapeType: Int] = [:]

    // MARK: - Init

    init() {
        recentFileURLs = recentFileStore.urls
        syncHistoryState()
    }

    // MARK: - Derived

    var selectedShapes: [CADShape] { shapes.filter { selectedIDs.contains($0.id) } }

    var contentBounds: CGRect? { DocumentLayoutService.boundingRect(for: shapes) }

    var rulerOrigin: CGPoint {
        guard let bounds = contentBounds?.standardized else { return .zero }
        return CGPoint(x: bounds.minX, y: bounds.minY)
    }

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
        historyStore.record(label, shapes: shapes)
        syncHistoryState()
        isDirty = true
    }

    /// Restaure l'état à un index quelconque de l'historique.
    func jumpToHistory(index: Int) {
        guard let restoredShapes = historyStore.jump(to: index) else { return }
        shapes       = restoredShapes
        selectedIDs  = selectedIDs.filter { id in shapes.contains(where: { $0.id == id }) }
        syncHistoryState()
        isDirty      = historyStore.index > 0
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
            shapes[i].translate(by: delta)
        }
        isDirty = true
        // Pas de recordAction ici : géré par beginMove/commitMove
    }

    func moveSelectedShapes(from baseShapes: [UUID: CADShape], by delta: CGSize) {
        for id in selectedIDs {
            guard let base = baseShapes[id],
                  let i = shapes.firstIndex(where: { $0.id == id })
            else { continue }

            var moved = base
            moved.translate(by: delta)
            shapes[i] = moved
        }
        isDirty = true
        // Pas de recordAction ici : géré par beginMove/commitMove
    }

    func beginResize() {
        if preResizeShapes == nil { preResizeShapes = shapes }
    }

    func resizeShape(id: UUID, to bounds: CGRect) {
        guard let i = shapes.firstIndex(where: { $0.id == id }) else { return }
        shapes[i].resize(to: bounds)
        isDirty = true
    }

    func commitResize() {
        guard let pre = preResizeShapes else { return }
        preResizeShapes = nil
        let resized = shapes.contains { shape in
            guard let old = pre.first(where: { $0.id == shape.id }) else { return false }
            return old.bounds != shape.bounds
        }
        if resized { recordAction("Transformation") }
    }

    func beginPointEdit() {
        if prePointEditShapes == nil { prePointEditShapes = shapes }
    }

    func replaceShapeDuringPointEdit(_ shape: CADShape) {
        guard let i = shapes.firstIndex(where: { $0.id == shape.id }) else { return }
        shapes[i] = shape
        isDirty = true
    }

    func commitPointEdit() {
        guard let pre = prePointEditShapes else { return }
        prePointEditShapes = nil
        if pre != shapes { recordAction("Modification points") }
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

    @discardableResult
    func moveShapeInDisplayOrder(id sourceID: UUID,
                                 relativeTo targetID: UUID,
                                 insertAfterTarget: Bool) -> Bool {
        guard sourceID != targetID else { return false }

        let currentDisplayIDs = shapes.reversed().map(\.id)
        guard currentDisplayIDs.contains(sourceID) else { return false }

        var reorderedDisplayIDs = currentDisplayIDs.filter { $0 != sourceID }
        guard let targetIndex = reorderedDisplayIDs.firstIndex(of: targetID) else { return false }

        let insertionIndex = targetIndex + (insertAfterTarget ? 1 : 0)
        reorderedDisplayIDs.insert(sourceID, at: insertionIndex)

        guard reorderedDisplayIDs != currentDisplayIDs else { return false }

        let shapesByID = Dictionary(uniqueKeysWithValues: shapes.map { ($0.id, $0) })
        shapes = reorderedDisplayIDs.reversed().compactMap { shapesByID[$0] }
        recordAction("Réorganisation formes")
        return true
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
        resetHistory(label: "Nouveau document")
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

    func openRecent(_ url: URL) {
        let standardizedURL = url.standardizedFileURL

        guard FileManager.default.fileExists(atPath: standardizedURL.path) else {
            removeRecentFile(standardizedURL)
            showMissingRecentFileAlert(for: standardizedURL)
            return
        }

        do {
            let result = try SVGService.load(from: standardizedURL)
            applyLoadResult(result, url: standardizedURL)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func clearRecentFiles() {
        recentFileStore.clear()
        recentFileURLs = recentFileStore.urls
    }

    private func applyLoadResult(_ result: SVGLoadResult, url: URL) {
        let centeredContent = DocumentLayoutService.centerLoadedContent(
            result.shapes,
            in: result.virtualCanvasSize ?? result.canvasSize,
            defaultCanvasSize: Self.defaultCanvasSize,
            margin: importContentMargin
        )

        shapes = centeredContent.shapes
        counters = result.counters
        canvasSize = centeredContent.canvasSize
        unit = result.unit
        currentFileURL = url
        selectedIDs = []
        isDirty = false
        resetHistory(label: "Ouverture fichier")
        scrollTarget = centeredContent.bounds.map { CGPoint(x: $0.midX, y: $0.midY) }
            ?? CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        zoomToFitBounds = centeredContent.bounds
        registerRecentFile(url)
    }

    private func writeToURL(_ url: URL) {
        do {
            try SVGService.save(document: self, to: url)
            isDirty = false
            registerRecentFile(url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func resetHistory(label: String) {
        historyStore.reset(label: label, shapes: shapes)
        syncHistoryState()
    }

    private func syncHistoryState() {
        historyEntries = historyStore.entries
        historyIndex = historyStore.index
    }

    private func registerRecentFile(_ url: URL) {
        recentFileStore.register(url)
        recentFileURLs = recentFileStore.urls
    }

    private func removeRecentFile(_ url: URL) {
        recentFileStore.remove(url)
        recentFileURLs = recentFileStore.urls
    }

    private func showMissingRecentFileAlert(for url: URL) {
        let alert = NSAlert()
        alert.messageText = "Fichier récent introuvable"
        alert.informativeText = "Le fichier « \(url.lastPathComponent) » n'est plus disponible à son emplacement d'origine."
        alert.alertStyle = .warning
        alert.runModal()
    }
}
