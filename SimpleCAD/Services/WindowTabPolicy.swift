import AppKit

enum WindowTabPolicy {
    private static let tabActionNames: Set<String> = [
        "newWindowForTab:",
        "toggleTabBar:",
        "toggleTabOverview:",
        "selectNextTab:",
        "selectPreviousTab:",
        "moveTabToNewWindow:",
        "mergeAllWindows:"
    ]

    static func disableApplicationTabs() {
        NSWindow.allowsAutomaticWindowTabbing = false
        DispatchQueue.main.async {
            removeTabCommandsFromMainMenu()
        }
    }

    static func configure(_ window: NSWindow) {
        window.tabbingMode = .disallowed
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        removeTabCommandsFromMainMenu()
    }

    static func removeTabCommandsFromMainMenu() {
        guard let menu = NSApp.mainMenu else { return }
        removeTabCommands(in: menu)
    }

    private static func removeTabCommands(in menu: NSMenu) {
        for item in menu.items {
            if let submenu = item.submenu {
                removeTabCommands(in: submenu)
            }
        }

        for item in menu.items where isTabCommand(item) {
            menu.removeItem(item)
        }

        removeRedundantSeparators(in: menu)
    }

    private static func isTabCommand(_ item: NSMenuItem) -> Bool {
        if let action = item.action,
           tabActionNames.contains(NSStringFromSelector(action)) {
            return true
        }

        let title = item.title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let words = title.split { !$0.isLetter }

        return title.contains("onglet") || words.contains("tab") || words.contains("tabs")
    }

    private static func removeRedundantSeparators(in menu: NSMenu) {
        while menu.items.first?.isSeparatorItem == true {
            menu.removeItem(at: 0)
        }

        while menu.items.last?.isSeparatorItem == true {
            menu.removeItem(at: menu.items.count - 1)
        }

        var index = menu.items.count - 1
        while index > 0 {
            if menu.items[index].isSeparatorItem && menu.items[index - 1].isSeparatorItem {
                menu.removeItem(at: index)
            }
            index -= 1
        }
    }
}
