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

        self.isDirectory = resourceValues?.isDirectory ?? false
        self.isSymlink = resourceValues?.isSymbolicLink ?? false
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
