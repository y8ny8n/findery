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
}
