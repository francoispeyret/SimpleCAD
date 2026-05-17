import SwiftUI
import AppKit

private let sidebarWidth: CGFloat = 240

struct ContentView: View {
    @EnvironmentObject var document: CADDocument

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {

                // ── Couche 0 : canvas plein écran ─────────────────
                CanvasScrollView()
                    .frame(width: geo.size.width, height: geo.size.height)

                // ── Couche 1 : sidebar (bord gauche, pleine hauteur)
                SidebarView()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(NSColor.separatorColor).opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 10, x: 2, y: 4)
                    .padding(.top, 44)
                    .padding([.leading, .trailing], 15)
                    .padding(.bottom, 28)
                    .frame(width: sidebarWidth, height: geo.size.height)

                // ── Couche 2 : toolbar flottante ──────────────────
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 15) {
                        Color.clear.frame(width: sidebarWidth)
                        ToolbarView()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(NSColor.separatorColor).opacity(0.25), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 6)
                            .padding(.trailing, 28)
                            .padding(.top, 8)
                    }
                    Spacer()
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea(.all)
        .frame(minWidth: 960, minHeight: 680)
        .onAppear { maximiseWindow() }
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
