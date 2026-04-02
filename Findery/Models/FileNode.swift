import Foundation
import UniformTypeIdentifiers

struct FileNode: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    let isSymlink: Bool
    let size: Int64
    let dateModified: Date
    let kind: String
    let fileExtension: String

    init(url: URL) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent

        let resourceValues = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .localizedTypeDescriptionKey
        ])

        self.isSymlink = resourceValues?.isSymbolicLink ?? false

        // 심볼릭 링크가 디렉토리를 가리키는 경우 (/tmp → /private/tmp 등)
        if self.isSymlink {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            self.isDirectory = isDir.boolValue
        } else {
            self.isDirectory = resourceValues?.isDirectory ?? false
        }
        self.size = Int64(resourceValues?.fileSize ?? 0)
        self.dateModified = resourceValues?.contentModificationDate ?? Date.distantPast
        self.kind = resourceValues?.localizedTypeDescription ?? "Unknown"
        self.fileExtension = url.pathExtension.lowercased()
    }

    var formattedSize: String {
        if isDirectory { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
