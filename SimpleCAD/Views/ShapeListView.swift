import SwiftUI
import UniformTypeIdentifiers

struct ShapeListView: View {
    @EnvironmentObject var document: CADDocument
    @State private var editingID:    UUID? = nil
    @State private var editingName:  String = ""
    @State private var draggingID:   UUID? = nil
    @State private var dropTargetID: UUID? = nil

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
                                isDropTarget: dropTargetID == shape.id,
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
                            // ── Drag source ──────────────────────────
                            .onDrag {
                                draggingID = shape.id
                                return NSItemProvider(object: shape.id.uuidString as NSString)
                            }
                            // ── Drop target ──────────────────────────
                            .onDrop(
                                of: [UTType.plainText],
                                delegate: ShapeDropDelegate(
                                    targetID:    shape.id,
                                    document:    document,
                                    draggingID:  $draggingID,
                                    dropTargetID: $dropTargetID
                                )
                            )

                            Divider().padding(.leading, 8)
                        }
                    }
                    .padding(.vertical, 2)
                }
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
}

// MARK: - ShapeRow

private struct ShapeRow: View {
    let shape:           CADShape
    let isSelected:      Bool
    let isEditing:       Bool
    @Binding var editingName: String
    let isDragging:      Bool
    let isDropTarget:    Bool
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
        .background(rowBackground)
        // Drop indicator: blue line on top edge when this row is the drop target
        .overlay(alignment: .top) {
            if isDropTarget {
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

// MARK: - DropDelegate

private struct ShapeDropDelegate: DropDelegate {
    let targetID:     UUID
    let document:     CADDocument
    @Binding var draggingID:   UUID?
    @Binding var dropTargetID: UUID?

    func validateDrop(info: DropInfo) -> Bool {
        guard let src = draggingID else { return false }
        return src != targetID
    }

    func dropEntered(info: DropInfo) {
        guard draggingID != nil, draggingID != targetID else { return }
        withAnimation(.easeInOut(duration: 0.15)) { dropTargetID = targetID }
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if dropTargetID == targetID { dropTargetID = nil }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggingID   = nil
            dropTargetID = nil
        }

        guard let fromID = draggingID,
              let fromIdx = document.shapes.firstIndex(where: { $0.id == fromID }),
              let toIdx   = document.shapes.firstIndex(where: { $0.id == targetID }),
              fromIdx != toIdx
        else { return false }

        withAnimation {
            let dest = toIdx > fromIdx ? toIdx + 1 : toIdx
            document.shapes.move(fromOffsets: IndexSet(integer: fromIdx), toOffset: dest)
            document.recordAction("Réorganisation calques")
        }
        return true
    }
}
