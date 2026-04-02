import AppKit
import UniformTypeIdentifiers

final class IconCache {
    private var cache: [String: NSImage] = [:]
    private let folderIcon: NSImage

    init() {
        folderIcon = NSWorkspace.shared.icon(for: UTType.folder)
        folderIcon.size = NSSize(width: 16, height: 16)
    }

    func icon(for node: FileNode) -> NSImage {
        if node.isDirectory {
            return folderIcon
        }

        let ext = node.fileExtension
        if let cached = cache[ext] {
            return cached
        }

        let utType = UTType(filenameExtension: ext) ?? .data
        let icon = NSWorkspace.shared.icon(for: utType)
        icon.size = NSSize(width: 16, height: 16)
        cache[ext] = icon
        return icon
    }
}
