import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var document: CADDocument

    var body: some View {
        HStack(spacing: 0) {

            // Outil actif
            HStack(spacing: 4) {
                Image(systemName: document.currentTool.sfSymbol)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(document.currentTool.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            separator

            // Info de sélection ou compte
            if !document.selectedShapes.isEmpty {
                let shape = document.selectedShapes[0]
                let u = document.unit
                HStack(spacing: 6) {
                    statLabel("x", u.formatValue(Double(shape.bounds.origin.x)))
                    statLabel("y", u.formatValue(Double(shape.bounds.origin.y)))
                    statLabel("l", u.formatValue(Double(shape.bounds.width)))
                    statLabel("h", u.formatValue(Double(shape.bounds.height)))
                    Text(u.rawValue)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("\(document.shapes.count) forme\(document.shapes.count != 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            separator

            // Nombre total quand sélection active
            if !document.selectedShapes.isEmpty {
                Text("\(document.shapes.count) forme\(document.shapes.count != 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                separator
            }

            // Taille du canevas
            let u = document.unit
            let w = u.formatValue(Double(document.canvasSize.width))
            let h = u.formatValue(Double(document.canvasSize.height))
            Text("\(w) × \(h) \(u.rawValue)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            // Indicateur de modification non sauvegardée
            if document.isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
                    .help("Modifications non enregistrées")
            }
        }
        .frame(height: 22)
    }

    private var separator: some View {
        Text(" | ")
            .font(.caption)
            .foregroundColor(Color.secondary.opacity(0.4))
    }

    private func statLabel(_ key: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Text("\(key):")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}
