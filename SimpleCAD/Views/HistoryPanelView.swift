import SwiftUI

struct HistoryPanelView: View {
    @EnvironmentObject var document: CADDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────
            HStack {
                Text("Historique")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(document.historyIndex + 1) / \(document.historyEntries.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // ── Liste ─────────────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(document.historyEntries.enumerated()), id: \.element.id) { idx, entry in
                            HistoryRow(
                                entry:     entry,
                                index:     idx,
                                isCurrent: idx == document.historyIndex,
                                isFuture:  idx > document.historyIndex,
                                isLast:    idx == document.historyEntries.count - 1
                            )
                            .id(entry.id)
                            .contentShape(Rectangle())
                            .onTapGesture { document.jumpToHistory(index: idx) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                // Faire défiler vers l'entrée courante quand l'index change
                .onChange(of: document.historyIndex) {
                    guard document.historyIndex < document.historyEntries.count else { return }
                    let id = document.historyEntries[document.historyIndex].id
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                .onAppear {
                    guard document.historyIndex < document.historyEntries.count else { return }
                    let id = document.historyEntries[document.historyIndex].id
                    proxy.scrollTo(id, anchor: .center)
                }
            }

            Divider()

            // ── Boutons Annuler / Rétablir ────────────────────────────
            HStack(spacing: 8) {
                Button {
                    document.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .help("Annuler (⌘Z)")
                .disabled(!document.canUndo)

                Button {
                    document.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .help("Rétablir (⌘⇧Z)")
                .disabled(!document.canRedo)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}

// MARK: - HistoryRow

private struct HistoryRow: View {
    let entry:     HistoryEntry
    let index:     Int
    let isCurrent: Bool
    let isFuture:  Bool
    let isLast:    Bool

    var body: some View {
        HStack(spacing: 0) {

            // ── Ligne de temps ────────────────────────────────────────
            VStack(spacing: 0) {
                // Segment haut
                Rectangle()
                    .fill(lineColor)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .opacity(index == 0 ? 0 : 1)

                // Point
                Circle()
                    .fill(dotFill)
                    .frame(width: dotSize, height: dotSize)
                    .overlay(
                        Circle()
                            .stroke(dotStroke, lineWidth: isCurrent ? 1.5 : 0)
                    )

                // Segment bas
                Rectangle()
                    .fill(lineColor)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .opacity(isLast ? 0 : 1)
            }
            .frame(width: 28)

            // ── Libellé ───────────────────────────────────────────────
            Text(entry.label)
                .font(.system(size: 12))
                .foregroundColor(isFuture ? .secondary.opacity(0.5) : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
        }
        .frame(height: 32)
        .background(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private var dotSize: CGFloat { isCurrent ? 10 : 7 }

    private var dotFill: Color {
        isCurrent ? Color.accentColor : (isFuture ? Color(NSColor.separatorColor).opacity(0.5) : Color(NSColor.separatorColor))
    }

    private var dotStroke: Color {
        isCurrent ? Color.white : Color.clear
    }

    private var lineColor: Color {
        isFuture ? Color(NSColor.separatorColor).opacity(0.3) : Color(NSColor.separatorColor)
    }
}
