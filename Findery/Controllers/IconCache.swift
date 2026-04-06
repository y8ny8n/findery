import AppKit
import UniformTypeIdentifiers
import QuickLookThumbnailing

final class IconCache {
    private var extensionCache: [String: NSImage] = [:]
    private var thumbnailCache: [URL: NSImage] = [:]
    private let folderIcon: NSImage
    private let thumbnailSize = NSSize(width: 16, height: 16)
    private let queue = DispatchQueue(label: "IconCache.thumbnail", attributes: .concurrent)

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif", "ico", "svg"
    ]

    init() {
        folderIcon = NSWorkspace.shared.icon(for: UTType.folder)
        folderIcon.size = NSSize(width: 16, height: 16)
    }

    func icon(for node: FileNode) -> NSImage {
        if node.isDirectory {
            return folderIcon
        }

        let ext = node.fileExtension.lowercased()

        // 이미지 파일: 썸네일 반환 (캐시 있으면 즉시, 없으면 비동기 로드 후 기본 아이콘)
        if Self.imageExtensions.contains(ext) {
            if let cached = thumbnailCache[node.url] {
                return cached
            }
            loadThumbnail(for: node)
            return extensionIcon(for: ext)
        }

        return extensionIcon(for: ext)
    }

    private func extensionIcon(for ext: String) -> NSImage {
        if let cached = extensionCache[ext] {
            return cached
        }
        let utType = UTType(filenameExtension: ext) ?? .data
        let icon = NSWorkspace.shared.icon(for: utType)
        icon.size = thumbnailSize
        extensionCache[ext] = icon
        return icon
    }

    private func loadThumbnail(for node: FileNode) {
        let url = node.url
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 32, height: 32),
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .thumbnail
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let self, let rep = representation else { return }
            let image = rep.nsImage
            image.size = self.thumbnailSize
            self.thumbnailCache[url] = image
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .finderyThumbnailLoaded, object: url)
            }
        }
    }

    func clearThumbnails() {
        thumbnailCache.removeAll()
    }
}
