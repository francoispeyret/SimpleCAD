import SwiftUI
import AppKit

// MARK: - Toolbar height constant (shared with SidebarView)
let toolbarHeight: CGFloat = 68

struct ToolbarView: View {
    @EnvironmentObject var document: CADDocument

    var body: some View {
        HStack(spacing: 0) {

            // ── Outils ───────────────────────────────────────────
            toolGroup

            separator

            // ── Couleurs ─────────────────────────────────────────
            colorGroup
                .padding(.horizontal, 12)

            separator

            // ── Épaisseur ────────────────────────────────────────
            strokeGroup
                .padding(.horizontal, 12)

            separator

            // ── Options ──────────────────────────────────────────
            optionGroup
                .padding(.horizontal, 12)

            Spacer()

            // ── Actions (droite) ─────────────────────────────────
            fileGroup
                .padding(.horizontal, 12)
        }
        .frame(height: toolbarHeight)
        .background(.regularMaterial)
    }

    private var separator: some View {
        Divider()
            .frame(height: 44)
    }

    // MARK: - Outils

    private var toolGroup: some View {
        HStack(spacing: 3) {
            ToolButton(tool: .select,    isSelected: document.currentTool == .select,    shortcut: "V") { activate(.select) }

            Divider().frame(height: 36).padding(.horizontal, 3)

            ForEach([Tool.rectangle, .square, .circle, .ellipse, .triangle, .line]) { tool in
                ToolButton(tool: tool, isSelected: document.currentTool == tool, shortcut: toolShortcut(tool)) { activate(tool) }
            }
        }
        .padding(.horizontal, 10)
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
        HStack(spacing: 14) {
            LabeledSwatch(label: "Remplissage", color: document.fillColor) { c in
                document.fillColor = c; document.applyFillToSelection()
            }
            LabeledSwatch(label: "Contour", color: document.strokeColor) { c in
                document.strokeColor = c; document.applyStrokeToSelection()
            }
        }
    }

    // MARK: - Épaisseur

    private var strokeGroup: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Épaisseur")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
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

    // MARK: - Options

    private var optionGroup: some View {
        HStack(spacing: 14) {
            Toggle(isOn: $document.showGrid) {
                Label("Grille", systemImage: "grid")
                    .font(.system(size: 12))
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: $document.showDimensions) {
                Label("Cotes", systemImage: "ruler")
                    .font(.system(size: 12))
            }
            .toggleStyle(.checkbox)

            unitPicker
        }
    }

    private var unitPicker: some View {
        HStack(spacing: 5) {
            Image(systemName: "ruler.fill")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Picker("", selection: $document.unit) {
                ForEach(DocumentUnit.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 60)
            .labelsHidden()
        }
    }

    // MARK: - Actions (droite)

    private var fileGroup: some View {
        HStack(spacing: 6) {
            ActionButton(icon: "doc.badge.plus",        tip: "Nouveau")         { document.new()  }
            ActionButton(icon: "folder",                tip: "Ouvrir…")         { document.open() }
            ActionButton(icon: "square.and.arrow.down", tip: "Enregistrer",
                         disabled: !document.isDirty)                           { document.save() }

            Divider().frame(height: 30).padding(.horizontal, 2)

            ActionButton(icon: "arrow.uturn.backward", tip: "Annuler (⌘Z)",
                         disabled: !document.canUndo)                           { document.undo() }
            ActionButton(icon: "arrow.uturn.forward",  tip: "Rétablir (⌘⇧Z)",
                         disabled: !document.canRedo)                           { document.redo() }
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
            .frame(width: 46, height: 54)
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

// MARK: - ActionButton (droite)

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
                        Color(NSColor.separatorColor).opacity(isHovering ? 0.8 : 0.4),
                        lineWidth: 1.5
                    )
            }
            .frame(width: 46, height: 28)
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
