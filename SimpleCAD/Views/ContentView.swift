import SwiftUI
import AppKit

private let toolbarLeftMargin: CGFloat = 42
private let toolbarRightMargin: CGFloat = 6
private let sidebarWidth: CGFloat = 260
private let trafficLightBackdropSize = CGSize(width: 80, height: 32)

struct ContentView: View {
    @EnvironmentObject var document: CADDocument
    @State private var keyboardMonitor: Any?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {

                // ── Couche 0 : canvas plein écran ─────────────────
                CanvasScrollView()
                    .frame(width: geo.size.width, height: geo.size.height)

                // ── Couche 0.5 : fond des boutons de fenêtre ──────
                TrafficLightBackdrop()
                    .frame(width: trafficLightBackdropSize.width,
                           height: trafficLightBackdropSize.height)
                    .padding(.top, 0)
                    .padding(.leading, 0)
                    .allowsHitTesting(false)

                // ── Couche 1 : toolbar (bord gauche, verticale) ───
                GlassEffectContainer {
                    ToolbarView()
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 44)
                .padding(.leading, toolbarLeftMargin)
                .padding(.trailing, toolbarRightMargin)
                .frame(width: toolbarWidth + toolbarLeftMargin + toolbarRightMargin,
                       alignment: .leading)

                // ── Couche 2 : sidebar (bord droit) ──────────────
                HStack(spacing: 0) {
                    Spacer()
                    GlassEffectContainer {
                        SidebarView()
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.top, 44)
                    .padding(.leading, 6)
                    .padding(.trailing, 28)
                    .padding(.bottom, 28)
                    .frame(width: sidebarWidth, height: geo.size.height)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea(.all)
        .frame(minWidth: 960, minHeight: 680)
        .onAppear {
            maximiseWindow()
            setupKeyboardShortcuts()
        }
        .onDisappear {
            if let keyboardMonitor {
                NSEvent.removeMonitor(keyboardMonitor)
                self.keyboardMonitor = nil
            }
        }
    }

    private func maximiseWindow() {
        DispatchQueue.main.async {
            guard let screen = NSScreen.main,
                  let window = NSApp.windows.first else { return }
            let frame = screen.visibleFrame.insetBy(dx: 40, dy: 40)
            window.setFrame(frame, display: true)
            window.center()
        }
    }

    private func setupKeyboardShortcuts() {
        guard keyboardMonitor == nil else { return }

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handleNumpadZoom(event) { return nil }
            guard let tool = toolShortcut(for: event) else { return event }

            document.currentTool = tool
            document.deselectAll()
            return nil
        }
    }

    /// Intercepte Cmd+[+/-/0] du pavé numérique (.numericPad flag ignoré par keyboardShortcut).
    private func handleNumpadZoom(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              event.modifierFlags.contains(.numericPad)
        else { return false }

        switch event.charactersIgnoringModifiers {
        case "+": document.zoomIn();    return true
        case "-": document.zoomOut();   return true
        case "0": document.resetZoom(); return true
        default:  return false
        }
    }

    private func toolShortcut(for event: NSEvent) -> Tool? {
        guard !isTextInputActive(),
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return nil }

        switch key {
        case "v": return .select
        case "r": return .rectangle
        case "q": return .square
        case "c": return .circle
        case "e": return .ellipse
        case "t": return .triangle
        case "l": return .line
        default:  return nil
        }
    }

    private func isTextInputActive() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView || responder is NSTextField { return true }

        if let view = responder as? NSView {
            return sequence(first: view, next: { $0.superview }).contains {
                $0 is NSTextField || $0 is NSComboBox || $0 is NSSearchField
            }
        }
        return false
    }
}

// MARK: - TrafficLightBackdrop

private struct TrafficLightBackdrop: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - SidebarView

private enum SidebarTab { case layers, history }

private struct SidebarView: View {
    @State private var tab: SidebarTab = .layers

    var body: some View {
        VStack(spacing: 0) {
            SidebarCanvasOptionsView()

            Divider()

            // ── Sélecteur d'onglet ────────────────────────────────
            HStack(spacing: 6) {
                SidebarTabButton(label: "Calques",    isSelected: tab == .layers)  { tab = .layers  }
                SidebarTabButton(label: "Historique", isSelected: tab == .history) { tab = .history }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // ── Contenu ───────────────────────────────────────────
            switch tab {
            case .layers:  ShapeListView()
            case .history: HistoryPanelView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - SidebarCanvasOptionsView

private struct SidebarCanvasOptionsView: View {
    @EnvironmentObject var document: CADDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan de travail")
                .font(.system(size: 12, weight: .semibold))

            gridModeMenu
            dimensionModeMenu
            unitPicker
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var gridModeMenu: some View {
        LabeledSidebarControl(label: "Grille") {
            Menu {
                ForEach(GridDisplayMode.allCases) { mode in
                    Button {
                        document.gridDisplayMode = mode
                    } label: {
                        HStack {
                            Text(mode.title)
                            if document.gridDisplayMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                SidebarMenuLabel(
                    icon: document.gridDisplayMode.sfSymbol,
                    title: document.gridDisplayMode.shortTitle
                )
            }
            .buttonStyle(.plain)
            .help("Afficher la grille")
        }
    }

    private var dimensionModeMenu: some View {
        LabeledSidebarControl(label: "Cotes") {
            Menu {
                ForEach(DimensionDisplayMode.allCases) { mode in
                    Button {
                        document.dimensionDisplayMode = mode
                    } label: {
                        HStack {
                            Text(mode.title)
                            if document.dimensionDisplayMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                SidebarMenuLabel(
                    icon: document.dimensionDisplayMode.sfSymbol,
                    title: document.dimensionDisplayMode.shortTitle
                )
            }
            .buttonStyle(.plain)
            .help("Afficher les cotes")
        }
    }

    private var unitPicker: some View {
        LabeledSidebarControl(label: "Dimensions") {
            Menu {
                ForEach(DocumentUnit.allCases) { unit in
                    Button {
                        document.unit = unit
                    } label: {
                        HStack {
                            Text(unit.rawValue)
                            if document.unit == unit {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                SidebarMenuLabel(
                    icon: "ruler.fill",
                    title: document.unit.rawValue
                )
            }
            .buttonStyle(.plain)
            .help("Choisir l'unité des dimensions")
        }
    }
}

private struct LabeledSidebarControl<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            content
        }
    }
}

private struct SidebarMenuLabel: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 14)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(NSColor.controlColor))
        )
    }
}

// MARK: - SidebarTabButton

private struct SidebarTabButton: View {
    let label:      String
    let isSelected: Bool
    let action:     () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? Color.accentColor : Color(NSColor.controlColor))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CanvasScrollView

struct CanvasScrollView: View {
    @EnvironmentObject var document: CADDocument

    var body: some View {
        CanvasScrollRepresentable()
            .background(Color(NSColor.underPageBackgroundColor))
    }
}
