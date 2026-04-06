import Foundation

// MARK: - Data Model

enum FavoriteEntry: Codable {
    case bookmark(path: String)
    case group(name: String, paths: [String])

    private enum CodingKeys: String, CodingKey {
        case type, path, name, paths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "group":
            let name = try container.decode(String.self, forKey: .name)
            let paths = try container.decode([String].self, forKey: .paths)
            self = .group(name: name, paths: paths)
        default:
            let path = try container.decode(String.self, forKey: .path)
            self = .bookmark(path: path)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bookmark(let path):
            try container.encode("bookmark", forKey: .type)
            try container.encode(path, forKey: .path)
        case .group(let name, let paths):
            try container.encode("group", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(paths, forKey: .paths)
        }
    }

    var isGroup: Bool {
        if case .group = self { return true }
        return false
    }
}

// MARK: - FavoritesManager

final class FavoritesManager {

    static let shared = FavoritesManager()

    private let key = "FinderyFavoritesV2"
    private let legacyKey = "FinderyFavorites"
    private let defaultPaths = ["Desktop", "Downloads", "Documents"]

    private(set) var entries: [FavoriteEntry] = []

    private init() {
        load()
    }

    // MARK: - Persistence

    private func load() {
        // V2 형식 로드
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([FavoriteEntry].self, from: data) {
            entries = saved
            return
        }

        // 기존 V1 형식 마이그레이션
        if let saved = UserDefaults.standard.array(forKey: legacyKey) as? [String] {
            entries = saved.map { .bookmark(path: $0) }
            save()
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return
        }

        // 기본 즐겨찾기
        let home = FileSystemController.homeDirectory
        var paths: [String] = [home.path]
        for name in defaultPaths {
            let url = home.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                paths.append(url.path)
            }
        }
        entries = paths.map { .bookmark(path: $0) }
        save()
    }

    private func save() {
        // 그룹 우선 정렬 유지
        let groups = entries.filter { $0.isGroup }
        let bookmarks = entries.filter { !$0.isGroup }
        entries = groups + bookmarks

        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: .finderyFavoritesChanged, object: nil)
    }

    // MARK: - Flat URL list (하위 호환)

    var favorites: [URL] {
        var result: [URL] = []
        for entry in entries {
            switch entry {
            case .bookmark(let path):
                result.append(URL(fileURLWithPath: path))
            case .group(_, let paths):
                result += paths.map { URL(fileURLWithPath: $0) }
            }
        }
        return result
    }

    // MARK: - Bookmark 추가/제거

    func add(_ url: URL) {
        guard !containsAnywhere(url) else { return }
        entries.append(.bookmark(path: url.path))
        save()
    }

    func remove(url: URL) {
        let std = url.standardizedFileURL
        entries.removeAll { entry in
            if case .bookmark(let path) = entry {
                return URL(fileURLWithPath: path).standardizedFileURL == std
            }
            return false
        }
        // 그룹 내부에서도 제거
        entries = entries.map { entry in
            guard case .group(let name, let paths) = entry else { return entry }
            let filtered = paths.filter { URL(fileURLWithPath: $0).standardizedFileURL != std }
            return .group(name: name, paths: filtered)
        }
        save()
    }

    func contains(_ url: URL) -> Bool {
        containsAnywhere(url)
    }

    private func containsAnywhere(_ url: URL) -> Bool {
        let std = url.standardizedFileURL
        for entry in entries {
            switch entry {
            case .bookmark(let path):
                if URL(fileURLWithPath: path).standardizedFileURL == std { return true }
            case .group(_, let paths):
                if paths.contains(where: { URL(fileURLWithPath: $0).standardizedFileURL == std }) { return true }
            }
        }
        return false
    }

    // MARK: - 그룹 관리

    func addGroup(name: String) {
        entries.append(.group(name: name, paths: []))
        save()
    }

    func renameGroup(at index: Int, to newName: String) {
        guard index >= 0, index < entries.count,
              case .group(_, let paths) = entries[index] else { return }
        entries[index] = .group(name: newName, paths: paths)
        save()
    }

    func removeGroup(at index: Int) {
        guard index >= 0, index < entries.count, entries[index].isGroup else { return }
        entries.remove(at: index)
        save()
    }

    func addToGroup(at groupIndex: Int, url: URL) {
        guard groupIndex >= 0, groupIndex < entries.count,
              case .group(let name, var paths) = entries[groupIndex] else { return }
        let std = url.standardizedFileURL
        guard !paths.contains(where: { URL(fileURLWithPath: $0).standardizedFileURL == std }) else { return }
        paths.append(url.path)
        entries[groupIndex] = .group(name: name, paths: paths)

        // 최상위 북마크에서 제거 (그룹으로 이동)
        entries.removeAll { entry in
            if case .bookmark(let path) = entry {
                return URL(fileURLWithPath: path).standardizedFileURL == std
            }
            return false
        }
        save()
    }

    func removeFromGroup(at groupIndex: Int, url: URL) {
        guard groupIndex >= 0, groupIndex < entries.count,
              case .group(let name, var paths) = entries[groupIndex] else { return }
        let std = url.standardizedFileURL
        paths.removeAll { URL(fileURLWithPath: $0).standardizedFileURL == std }
        entries[groupIndex] = .group(name: name, paths: paths)
        save()
    }

    func remove(at index: Int) {
        guard index >= 0, index < entries.count else { return }
        entries.remove(at: index)
        save()
    }

    // MARK: - 순서 변경

    func moveEntry(from sourceIndex: Int, to destIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < entries.count,
              destIndex >= 0, destIndex <= entries.count,
              sourceIndex != destIndex else { return }
        let entry = entries.remove(at: sourceIndex)
        let adjustedDest = destIndex > sourceIndex ? destIndex - 1 : destIndex
        entries.insert(entry, at: min(adjustedDest, entries.count))
        save()
    }

    func insertBookmark(path: String, at index: Int) {
        let url = URL(fileURLWithPath: path)
        guard !containsAnywhere(url) else { return }
        let clamped = max(0, min(index, entries.count))
        entries.insert(.bookmark(path: path), at: clamped)
        save()
    }

    // MARK: - 그룹 내 순서 변경

    func moveWithinGroup(at groupIndex: Int, url: URL, to destIndex: Int) {
        guard groupIndex >= 0, groupIndex < entries.count,
              case .group(let name, var paths) = entries[groupIndex] else { return }
        let std = url.standardizedFileURL
        guard let sourceIndex = paths.firstIndex(where: { URL(fileURLWithPath: $0).standardizedFileURL == std }) else { return }
        let path = paths.remove(at: sourceIndex)
        let adjusted = destIndex > sourceIndex ? destIndex - 1 : destIndex
        paths.insert(path, at: max(0, min(adjusted, paths.count)))
        entries[groupIndex] = .group(name: name, paths: paths)
        save()
    }

    // MARK: - 아이콘

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
                return "person.fill"
            }
            return "folder.fill"
        }
    }
}
