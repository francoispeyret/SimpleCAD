import AppKit
import Foundation

// MARK: - RecentFileStore

struct RecentFileStore {
    private static let defaultsKey = "SimpleCAD.recentFiles"
    private static let maxRecentFiles = 10

    private let userDefaults: UserDefaults
    private(set) var urls: [URL]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.urls = Self.loadURLs(from: userDefaults)
    }

    mutating func register(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        urls.removeAll { $0.standardizedFileURL.path == standardizedURL.path }
        urls.insert(standardizedURL, at: 0)

        if urls.count > Self.maxRecentFiles {
            urls = Array(urls.prefix(Self.maxRecentFiles))
        }

        persist()
        NSDocumentController.shared.noteNewRecentDocumentURL(standardizedURL)
    }

    mutating func remove(_ url: URL) {
        let standardizedPath = url.standardizedFileURL.path
        urls.removeAll { $0.standardizedFileURL.path == standardizedPath }
        persist()
    }

    mutating func clear() {
        urls = []
        persist()
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    private func persist() {
        let paths = urls.map { $0.standardizedFileURL.path }
        userDefaults.set(paths, forKey: Self.defaultsKey)
    }

    private static func loadURLs(from userDefaults: UserDefaults) -> [URL] {
        let paths = userDefaults.stringArray(forKey: defaultsKey) ?? []
        var seen: Set<String> = []

        return paths.compactMap { path in
            guard !path.isEmpty else { return nil }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard seen.insert(url.path).inserted else { return nil }
            return url
        }
    }
}
