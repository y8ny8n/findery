import Foundation

final class FileSystemController {

    static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    var showHiddenFiles = false

    func enumerate(directory url: URL) async -> [FileNode] {
        let showHidden = showHiddenFiles
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let items = self.enumerateSync(directory: url, showHidden: showHidden)
                continuation.resume(returning: items)
            }
        }
    }

    private func enumerateSync(directory url: URL, showHidden: Bool) -> [FileNode] {
        let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .localizedTypeDescriptionKey
            ],
            options: options
        ) else {
            return []
        }

        return contents
            .map { FileNode(url: $0) }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    static func expandTilde(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }

        let expanded: String
        if path.hasPrefix("~/") {
            expanded = (path as NSString).expandingTildeInPath
        } else if path == "~" {
            expanded = homeDirectory.path
        } else {
            expanded = path
        }

        let url = URL(fileURLWithPath: expanded)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else {
            return nil
        }

        return url
    }
}
