import SwiftUI
import AppKit

// MARK: - Toolbar width constant (shared with ContentView)
let toolbarWidth: CGFloat = 120

struct ToolbarView: View {
    @EnvironmentObject var document: CADDocument

    var body: some View {
        VStack(spacing: 0) {

            // ── Outils ───────────────────────────────────────────
            toolGroup

            separator

            // ── Couleurs ─────────────────────────────────────────
            colorGroup
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            separator

            // ── Zoom ─────────────────────────────────────────────
            zoomGroup
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            separator

            // ── Actions fichier (bas) ─────────────────────────────
            fileGroup
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(width: toolbarWidth)
    }

    private var separator: some View {
        Divider()
    }

    // MARK: - Outils

    private var toolGroup: some View {
        VStack(spacing: 4) {
            // Outil sélection (pleine largeur)
            ToolButton(tool: .select, isSelected: document.currentTool == .select, shortcut: "V") { activate(.select) }

            Divider().padding(.horizontal, 8).padding(.vertical, 2)

            // Formes en grille 2 colonnes
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach([Tool.rectangle, .square, .circle, .ellipse, .triangle, .line]) { tool in
                    ToolButton(tool: tool, isSelected: document.currentTool == tool, shortcut: toolShortcut(tool)) {
                        activate(tool)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
    }

    private func activate(_ tool: Tool) {
        document.currentTool = tool
        document.deselectAll()
    }

    private func toolShortcut(_ tool: Tool) -> String {
        switch tool {
        case .select: return "V"; case .rectangle: return "R"; case .square: return "Q"
        case .circle: return "C"; case .ellipse:   return "E"; case .triangle: return "T"
        case .line:   return "L"
        }
    }

    // MARK: - Couleurs

    private var colorGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledSwatch(label: "Remplissage", color: document.fillColor) { c in
                document.fillColor = c; document.applyFillToSelection()
            }
            LabeledSwatch(label: "Contour", color: document.strokeColor) { c in
                document.strokeColor = c; document.applyStrokeToSelection()
            }
            
            strokeGroup
        }
    }

    // MARK: - Épaisseur

    private var strokeGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                TextField("", value: $document.strokeWidth, format: .number)
                    .frame(width: 46)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13))
                Stepper("", value: $document.strokeWidth, in: 0.5...50, step: 0.5)
                    .labelsHidden()
                    .onChange(of: document.strokeWidth) { document.applyStrokeWidthToSelection() }
                Text("px")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Zoom

    private var zoomGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ActionButton(icon: "minus.magnifyingglass", tip: "Zoom arrière (⌘-)") {
                    document.zoomOut()
                }
                Button(action: { document.resetZoom() }) {
                    Text(zoomLabel)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(width: 46)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color(NSColor.controlColor)))
                }
                .buttonStyle(.plain)
                .help("Réinitialiser le zoom à 100% (⌘0)")
                ActionButton(icon: "plus.magnifyingglass", tip: "Zoom avant (⌘+)") {
                    document.zoomIn()
                }
            }
        }
    }

    private var zoomLabel: String {
        String(format: "%.0f%%", document.zoomLevel * 100)
    }

    // MARK: - Actions fichier (bas)

    private var fileGroup: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ActionButton(icon: "arrow.uturn.backward", tip: "Annuler (⌘Z)",
                             disabled: !document.canUndo)                      { document.undo() }
                ActionButton(icon: "arrow.uturn.forward",  tip: "Rétablir (⌘⇧Z)",
                             disabled: !document.canRedo)                      { document.redo() }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - ToolButton

private struct ToolButton: View {
    let tool:       Tool
    let isSelected: Bool
    let shortcut:   String
    let action:     () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: tool.sfSymbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                Text(shortcut)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected
                        ? Color.accentColor
                        : (isHovering ? Color(NSColor.controlColor) : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("\(tool.rawValue) (\(shortcut))")
    }
}

// MARK: - ActionButton

private struct ActionButton: View {
    let icon:     String
    let tip:      String
    var disabled: Bool = false
    let action:   () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(disabled ? .secondary.opacity(0.4) : .primary)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHovering && !disabled
                              ? Color(NSColor.controlColor)
                              : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { isHovering = $0 }
        .help(tip)
    }
}

// MARK: - LabeledSwatch

private struct LabeledSwatch: View {
    let label:    String
    let color:    CADColor
    let onChange: (CADColor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            ColorSwatch(color: color, onChange: onChange)
        }
    }
}

// MARK: - ColorSwatch

private struct ColorSwatch: View {
    var color:    CADColor
    var onChange: (CADColor) -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: openPanel) {
            ZStack {
                CheckerboardView()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(color.nsColor))
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        Color(NSColor.systemGray).opacity(isHovering ? 0.9 : 0.65),
                        lineWidth: 1
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Cliquer pour choisir une couleur")
    }

    private func openPanel() {
        ColorPanelCoordinator.shared.open(color: color, onChange: onChange)
    }
}

// MARK: - CheckerboardView

private struct CheckerboardView: View {
    private let cell: CGFloat = 4
    var body: some View {
        Canvas { ctx, size in
            let cols = Int(ceil(size.width  / cell))
            let rows = Int(ceil(size.height / cell))
            for row in 0..<rows {
                for col in 0..<cols {
                    let rect = CGRect(x: CGFloat(col)*cell, y: CGFloat(row)*cell,
                                     width: cell, height: cell)
                    ctx.fill(Path(rect), with: .color((row+col)%2==0 ? .white : Color(white: 0.75)))
                }
            }
        }
    }
}

// MARK: - ColorPanelCoordinator

private final class ColorPanelCoordinator: NSObject {
    static let shared = ColorPanelCoordinator()
    private var onChange: ((CADColor) -> Void)?

    func open(color: CADColor, onChange: @escaping (CADColor) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.color = color.nsColor
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.isContinuous = true
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func colorChanged(_ sender: NSColorPanel) {
        onChange?(CADColor(sender.color))
    }
}
