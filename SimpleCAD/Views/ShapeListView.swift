import SwiftUI

private let shapeRowHeight: CGFloat = 42
private let shapeListCoordinateSpace = "ShapeListReorderSpace"

struct ShapeListView: View {
    @EnvironmentObject var document: CADDocument
    @State private var editingID:    UUID? = nil
    @State private var editingName:  String = ""
    @State private var draggingID:   UUID? = nil
    @State private var dropTarget:   ShapeDropTarget? = nil
    @State private var rowFrames:    [UUID: CGRect] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ───────────────────────────────────────────────
            HStack {
                Text("Calques")
                    .font(.system(size: 12, weight: .semibold))
                Text("(\(document.shapes.count))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // ── List ─────────────────────────────────────────────────
            if document.shapes.isEmpty {
                Spacer()
                Text("Aucune forme")
                    .foregroundColor(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(document.shapes.reversed()) { shape in
                            ShapeRow(
                                shape:        shape,
                                isSelected:   document.selectedIDs.contains(shape.id),
                                isEditing:    editingID == shape.id,
                                editingName:  $editingName,
                                isDragging:   draggingID == shape.id,
                                dropPlacement: dropTarget?.id == shape.id ? dropTarget?.placement : nil,
                                onTap: {
                                    if editingID != shape.id { document.selectShape(id: shape.id) }
                                },
                                onDoubleTap: {
                                    editingID   = shape.id
                                    editingName = shape.name
                                },
                                onRenameCommit: { commitRename(id: shape.id) },
                                onRenameCancel: { editingID = nil }
                            )
                            .background(rowFrameReader(for: shape.id))
                            .simultaneousGesture(reorderGesture(for: shape.id))

                            Divider().padding(.leading, 8)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .coordinateSpace(name: shapeListCoordinateSpace)
                .onPreferenceChange(ShapeRowFramePreferenceKey.self) { rowFrames = $0 }
            }

            Divider()

            // ── Footer ────────────────────────────────────────────────
            HStack(spacing: 8) {
                Button { document.removeSelected() } label: {
                    Image(systemName: "minus").frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .help("Supprimer")
                .disabled(document.selectedIDs.isEmpty)

                Divider().frame(height: 16)

                Button { document.bringToFront() } label: {
                    Image(systemName: "square.3.layers.3d.top.filled").frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .help("Premier plan")
                .disabled(document.selectedIDs.isEmpty)

                Button { document.sendToBack() } label: {
                    Image(systemName: "square.3.layers.3d.bottom.filled").frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .help("Arrière-plan")
                .disabled(document.selectedIDs.isEmpty)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
    }

    private func commitRename(id: UUID) {
        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { document.renameShape(id: id, to: trimmed) }
        editingID = nil
    }

    private func rowFrameReader(for id: UUID) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ShapeRowFramePreferenceKey.self,
                value: [id: proxy.frame(in: .named(shapeListCoordinateSpace))]
            )
        }
    }

    private func reorderGesture(for id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(shapeListCoordinateSpace))
            .onChanged { value in
                guard editingID == nil, document.shapes.count > 1 else { return }

                if draggingID == nil {
                    draggingID = id
                    document.selectShape(id: id)
                }
                guard draggingID == id else { return }

                dropTarget = dropTarget(for: value.location, draggingID: id)
            }
            .onEnded { value in
                guard editingID == nil else {
                    clearDragState()
                    return
                }
                let finalTarget = dropTarget(for: value.location, draggingID: id) ?? dropTarget

                if let finalTarget {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        _ = document.moveShapeInDisplayOrder(
                            id: id,
                            relativeTo: finalTarget.id,
                            insertAfterTarget: finalTarget.placement == .after
                        )
                    }
                }
                clearDragState()
            }
    }

    private func dropTarget(for point: CGPoint, draggingID: UUID) -> ShapeDropTarget? {
        let displayIDs = document.shapes.reversed().map(\.id)
        let orderedFrames = displayIDs.compactMap { id -> (id: UUID, frame: CGRect)? in
            guard let frame = rowFrames[id] else { return nil }
            return (id, frame)
        }

        guard !orderedFrames.isEmpty else { return nil }

        for entry in orderedFrames where entry.frame.contains(point) {
            return dropTarget(
                id: entry.id,
                placement: point.y < entry.frame.midY ? .before : .after,
                draggingID: draggingID
            )
        }

        if let first = orderedFrames.first, point.y < first.frame.minY {
            return dropTarget(id: first.id, placement: .before, draggingID: draggingID)
        }

        if let last = orderedFrames.last, point.y > last.frame.maxY {
            return dropTarget(id: last.id, placement: .after, draggingID: draggingID)
        }

        for index in 0..<(orderedFrames.count - 1) {
            let upper = orderedFrames[index]
            let lower = orderedFrames[index + 1]
            if point.y > upper.frame.maxY, point.y < lower.frame.minY {
                return dropTarget(id: upper.id, placement: .after, draggingID: draggingID)
            }
        }

        return nil
    }

    private func dropTarget(id: UUID,
                            placement: ShapeDropPlacement,
                            draggingID: UUID) -> ShapeDropTarget? {
        id == draggingID ? nil : ShapeDropTarget(id: id, placement: placement)
    }

    private func clearDragState() {
        draggingID = nil
        dropTarget = nil
    }
}

// MARK: - ShapeRow

private struct ShapeRow: View {
    let shape:           CADShape
    let isSelected:      Bool
    let isEditing:       Bool
    @Binding var editingName: String
    let isDragging:      Bool
    let dropPlacement:   ShapeDropPlacement?
    let onTap:           () -> Void
    let onDoubleTap:     () -> Void
    let onRenameCommit:  () -> Void
    let onRenameCancel:  () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {

            // ── Drag handle ───────────────────────────────────────────
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.4))
                .frame(width: 12)

            // ── Shape icon + color swatch ─────────────────────────────
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(shape.fillColor.nsColor))
                    .frame(width: 18, height: 18)
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color(shape.strokeColor.nsColor), lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                Image(systemName: shape.type.sfSymbol)
                    .font(.system(size: 8))
                    .foregroundColor(contrastColor(for: shape.fillColor))
            }

            // ── Name ──────────────────────────────────────────────────
            if isEditing {
                TextField("Nom", text: $editingName)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(onRenameCommit)
                    .onExitCommand(perform: onRenameCancel)
                    .onChange(of: isEditing) {
                        isFocused = isEditing
                    }
                    .onAppear { isFocused = true }
            } else {
                Text(shape.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2, perform: onDoubleTap)
                    .onTapGesture(count: 1, perform: onTap)
            }

            Spacer(minLength: 2)

            // ── Dimension badge ───────────────────────────────────────
            Text(String(format: "%.0f×%.0f", shape.widthMM, shape.heightMM))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .layoutPriority(-1)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(height: shapeRowHeight)
        .background(rowBackground)
        // Indicateur de dépôt : ligne bleue au-dessus ou en-dessous de la cible.
        .overlay(alignment: .top) {
            if dropPlacement == .before {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .bottom) {
            if dropPlacement == .after {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .opacity(isDragging ? 0.4 : 1.0)
        .contentShape(Rectangle())
    }

    private var rowBackground: some View {
        Group {
            if isSelected {
                Color.accentColor.opacity(0.12)
            } else {
                Color.clear
            }
        }
    }

    private func contrastColor(for bg: CADColor) -> Color {
        let lum = 0.2126 * bg.red + 0.7152 * bg.green + 0.0722 * bg.blue
        return lum < 0.5 ? .white : .black
    }
}

// MARK: - Reorder helpers

private enum ShapeDropPlacement {
    case before
    case after
}

private struct ShapeDropTarget: Equatable {
    let id: UUID
    let placement: ShapeDropPlacement
}

private struct ShapeRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
