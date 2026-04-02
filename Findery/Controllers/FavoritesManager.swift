import Foundation

final class FavoritesManager {

    static let shared = FavoritesManager()

    private let key = "FinderyFavorites"
    private let defaultPaths = ["Desktop", "Downloads", "Documents"]

    private(set) var favorites: [URL] = []

    private init() {
        load()
    }

    private func load() {
        if let saved = UserDefaults.standard.array(forKey: key) as? [String] {
            favorites = saved.compactMap { URL(fileURLWithPath: $0) }
        } else {
            // 기본 즐겨찾기
            let home = FileSystemController.homeDirectory
            favorites = defaultPaths.compactMap { name in
                let url = home.appendingPathComponent(name)
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            }
            favorites.insert(home, at: 0)
            save()
        }
    }

    private func save() {
        let paths = favorites.map(\.path)
        UserDefaults.standard.set(paths, forKey: key)
    }

    func add(_ url: URL) {
        guard !favorites.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else { return }
        favorites.append(url)
        save()
        NotificationCenter.default.post(name: .finderyFavoritesChanged, object: nil)
    }

    func remove(at index: Int) {
        guard index >= 0, index < favorites.count else { return }
        favorites.remove(at: index)
        save()
        NotificationCenter.default.post(name: .finderyFavoritesChanged, object: nil)
    }

    func remove(url: URL) {
        favorites.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        save()
        NotificationCenter.default.post(name: .finderyFavoritesChanged, object: nil)
    }

    func contains(_ url: URL) -> Bool {
        favorites.contains { $0.standardizedFileURL == url.standardizedFileURL }
    }

    static func icon(for url: URL) -> String {
        let name = url.lastPathComponent
        switch name {
        case "Desktop": return "desktopcomputer"
        case "Downloads": return "arrow.down.circle.fill"
        case "Documents": return "doc.fill"
        case "Applications": return "app.fill"
        case "Pictures": return "photo.fill"
        case "Music": return "music.note"
        case "Movies": return "film.fill"
        default:
            if url.path == FileSystemController.homeDirectory.path {
                return "house.fill"
            }
            return "folder.fill"
        }
    }
}
