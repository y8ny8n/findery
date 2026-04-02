import Foundation
import AppKit

final class FileOperations {

    enum FileError: LocalizedError {
        case alreadyExists(String)
        case permissionDenied
        case operationFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyExists(let name):
                return "'\(name)' 이름의 항목이 이미 존재합니다."
            case .permissionDenied:
                return "이 작업을 수행할 권한이 없습니다."
            case .operationFailed(let reason):
                return reason
            }
        }
    }

    func rename(at url: URL, to newName: String) throws -> URL {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)

        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            throw FileError.alreadyExists(newName)
        }

        try FileManager.default.moveItem(at: url, to: newURL)
        return newURL
    }

    func createNewFolder(in directory: URL, name: String = "새 폴더") throws -> URL {
        var folderName = name
        var folderURL = directory.appendingPathComponent(folderName)
        var counter = 1

        while FileManager.default.fileExists(atPath: folderURL.path) {
            counter += 1
            folderName = "\(name) \(counter)"
            folderURL = directory.appendingPathComponent(folderName)
        }

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        return folderURL
    }

    func moveToTrash(urls: [URL]) throws {
        for url in urls {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }

    func openFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: - Clipboard

    func copyToClipboard(urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    func copyFiles(_ sources: [URL], to destination: URL) throws {
        for source in sources {
            var destURL = destination.appendingPathComponent(source.lastPathComponent)
            destURL = uniqueURL(destURL)
            try FileManager.default.copyItem(at: source, to: destURL)
        }
    }

    func moveFiles(_ sources: [URL], to destination: URL) throws {
        for source in sources {
            var destURL = destination.appendingPathComponent(source.lastPathComponent)
            destURL = uniqueURL(destURL)
            try FileManager.default.moveItem(at: source, to: destURL)
        }
    }

    private func uniqueURL(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }

        let directory = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var counter = 2
        while true {
            let newName = ext.isEmpty ? "\(name) \(counter)" : "\(name) \(counter).\(ext)"
            let newURL = directory.appendingPathComponent(newName)
            if !FileManager.default.fileExists(atPath: newURL.path) {
                return newURL
            }
            counter += 1
        }
    }
}
