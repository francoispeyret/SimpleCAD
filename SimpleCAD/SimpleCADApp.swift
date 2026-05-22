import SwiftUI

@main
struct SimpleCADApp: App {
    @StateObject private var document = CADDocument()

    init() {
        WindowTabPolicy.disableApplicationTabs()
    }

    var body: some Scene {
        Window("SimpleCAD", id: "main") {
            ContentView()
                .environmentObject(document)
                .onOpenURL { url in document.open(url: url) }
        }
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("Nouveau")              { document.new()    }.keyboardShortcut("n")
                Button("Ouvrir…")             { document.open()   }.keyboardShortcut("o")
                Menu("Ouvrir récent") {
                    if document.recentFileURLs.isEmpty {
                        Button("Aucun fichier récent") { }
                            .disabled(true)
                    } else {
                        ForEach(document.recentFileURLs, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                document.openRecent(url)
                            }
                            .help(url.path)
                        }

                        Divider()

                        Button("Effacer le menu") {
                            document.clearRecentFiles()
                        }
                    }
                }
                Divider()
                Button("Enregistrer")         { document.save()   }.keyboardShortcut("s")
                Button("Enregistrer sous…")   { document.saveAs() }.keyboardShortcut("S")
            }
            // Edit menu
            CommandGroup(replacing: .undoRedo) {
                Button("Annuler")             { document.undo()   }.keyboardShortcut("z")
                    .disabled(!document.canUndo)
                Button("Rétablir")            { document.redo()   }.keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!document.canRedo)
            }
            CommandMenu("Présentation") {
                Button("Zoom avant")  { document.zoomIn()    }.keyboardShortcut("=", modifiers: .command)
                Button("Zoom arrière") { document.zoomOut()  }.keyboardShortcut("-", modifiers: .command)
                Button("Zoom 100%")   { document.resetZoom() }.keyboardShortcut("0", modifiers: .command)
            }
            CommandGroup(after: .undoRedo) {
                Divider()
                Button("Tout sélectionner")   { document.selectAll()   }.keyboardShortcut("a")
                Button("Tout désélectionner") { document.deselectAll() }.keyboardShortcut("d")
                Divider()
                Button("Supprimer") { document.removeSelected() }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(document.selectedIDs.isEmpty)
                Divider()
                Button("Premier plan") { document.bringToFront() }
                    .disabled(document.selectedIDs.isEmpty)
                Button("Arrière-plan") { document.sendToBack()   }
                    .disabled(document.selectedIDs.isEmpty)
            }
        }
    }
}
