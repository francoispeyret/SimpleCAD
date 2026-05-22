import SwiftUI
import AppKit

private let toolbarLeftMargin: CGFloat = 42
private let toolbarRightMargin: CGFloat = 6
private let sidebarWidth: CGFloat = 260

struct ContentView: View {
    @EnvironmentObject var document: CADDocument
    @State private var keyboardMonitor: Any?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {

                // ── Couche 0 : canvas plein écran ─────────────────
                CanvasScrollView()
                    .frame(width: geo.size.width, height: geo.size.height)

                // ── Couche 1 : toolbar (bord gauche, verticale) ───
                GlassEffectContainer {
                    ToolbarView()
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 44)
                .padding(.leading, toolbarLeftMargin)
                .padding(.trailing, toolbarRightMargin)
                .padding(.bottom, 28)
                .frame(width: toolbarWidth + toolbarLeftMargin + toolbarRightMargin,
                       height: geo.size.height,
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
                    .padding(.trailing, 15)
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
// MARK: - SidebarView

private enum SidebarTab { case layers, history }

private struct SidebarView: View {
    @State private var tab: SidebarTab = .layers

    var body: some View {
        VStack(spacing: 0) {

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
