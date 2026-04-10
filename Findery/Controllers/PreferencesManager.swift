import Foundation
import AppKit

final class PreferencesManager {
    static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard

    // MARK: - Sort Settings

    var defaultSortColumn: String {
        get { defaults.string(forKey: "defaultSortColumn") ?? "Name" }
        set { defaults.set(newValue, forKey: "defaultSortColumn") }
    }

    var defaultSortAscending: Bool {
        get { defaults.object(forKey: "defaultSortAscending") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "defaultSortAscending") }
    }

    var foldersFirst: Bool {
        get { defaults.object(forKey: "foldersFirst") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "foldersFirst") }
    }

    // MARK: - File Type Associations

    private var associationsCache: [String: Data] {
        get { defaults.dictionary(forKey: "fileTypeAssociations") as? [String: Data] ?? [:] }
        set { defaults.set(newValue, forKey: "fileTypeAssociations") }
    }

    func appURL(forExtension ext: String) -> URL? {
        let key = ext.lowercased()
        guard let bookmark = associationsCache[key] else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            removeDefaultApp(forExtension: key)
            return nil
        }
        if stale {
            // Re-save fresh bookmark
            if let fresh = try? url.bookmarkData() {
                var cache = associationsCache
                cache[key] = fresh
                associationsCache = cache
            }
        }
        return url
    }

    func setDefaultApp(_ appURL: URL, forExtension ext: String) {
        guard let bookmark = try? appURL.bookmarkData() else { return }
        var cache = associationsCache
        cache[ext.lowercased()] = bookmark
        associationsCache = cache
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    func removeDefaultApp(forExtension ext: String) {
        var cache = associationsCache
        cache.removeValue(forKey: ext.lowercased())
        associationsCache = cache
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    func allAssociations() -> [(ext: String, appURL: URL)] {
        return associationsCache.compactMap { key, bookmark in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
            return (ext: key, appURL: url)
        }.sorted { $0.ext < $1.ext }
    }
}

extension Notification.Name {
    static let preferencesChanged = Notification.Name("FinderyPreferencesChanged")
}
