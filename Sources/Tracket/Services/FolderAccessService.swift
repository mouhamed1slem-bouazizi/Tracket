import Foundation

@MainActor
final class FolderAccessService {
    private let bookmarksKey = "tracket.folder-bookmarks.v1"
    private let defaults: UserDefaults
    private var activeURLs: [String: URL] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func restoreAccess(for paths: [String]) {
        let wanted = Set(paths)
        for (path, data) in storedBookmarks where wanted.contains(path) {
            activateBookmark(data, expectedPath: path)
        }
    }

    func remember(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard normalized.isFileURL,
              let data = try? normalized.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
              ) else { return }

        var bookmarks = storedBookmarks
        bookmarks[normalized.path] = data
        defaults.set(bookmarks, forKey: bookmarksKey)
        activateBookmark(data, expectedPath: normalized.path)
    }

    func forget(path: String) {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        if let url = activeURLs.removeValue(forKey: normalized) {
            url.stopAccessingSecurityScopedResource()
        }
        var bookmarks = storedBookmarks
        bookmarks.removeValue(forKey: normalized)
        defaults.set(bookmarks, forKey: bookmarksKey)
    }

    func reset() {
        for url in activeURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
        activeURLs.removeAll()
        defaults.removeObject(forKey: bookmarksKey)
    }

    private var storedBookmarks: [String: Data] {
        defaults.dictionary(forKey: bookmarksKey)?.compactMapValues { $0 as? Data } ?? [:]
    }

    private func activateBookmark(_ data: Data, expectedPath: String) {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return }

        let normalized = url.standardizedFileURL
        guard normalized.path == expectedPath else { return }
        if stale { remember(normalized) }
        if activeURLs[expectedPath] == nil,
           normalized.startAccessingSecurityScopedResource() {
            activeURLs[expectedPath] = normalized
        }
    }
}
