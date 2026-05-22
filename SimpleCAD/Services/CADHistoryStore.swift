import Foundation

// MARK: - HistoryEntry

struct HistoryEntry: Identifiable {
    let id = UUID()
    let label: String
    let shapes: [CADShape]
}

// MARK: - CADHistoryStore

struct CADHistoryStore {
    private(set) var entries: [HistoryEntry]
    private(set) var index: Int
    private let maxEntries: Int

    init(initialLabel: String = "Nouveau document",
         initialShapes: [CADShape] = [],
         maxEntries: Int = 51) {
        self.entries = [HistoryEntry(label: initialLabel, shapes: initialShapes)]
        self.index = 0
        self.maxEntries = maxEntries
    }

    var canUndo: Bool { index > 0 }
    var canRedo: Bool { index < entries.count - 1 }

    mutating func reset(label: String, shapes: [CADShape]) {
        entries = [HistoryEntry(label: label, shapes: shapes)]
        index = 0
    }

    mutating func record(_ label: String, shapes: [CADShape]) {
        if index < entries.count - 1 {
            entries = Array(entries.prefix(index + 1))
        }

        entries.append(HistoryEntry(label: label, shapes: shapes))
        index = entries.count - 1

        if entries.count > maxEntries {
            entries.removeFirst()
            index = entries.count - 1
        }
    }

    mutating func jump(to targetIndex: Int) -> [CADShape]? {
        guard targetIndex >= 0,
              targetIndex < entries.count,
              targetIndex != index else { return nil }

        index = targetIndex
        return entries[index].shapes
    }
}
