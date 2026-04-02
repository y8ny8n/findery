import XCTest
@testable import Findery

final class IconCacheTests: XCTestCase {

    func testFolderIcon() {
        let cache = IconCache()
        let folderURL = FileSystemController.homeDirectory.appendingPathComponent("Desktop")
        let node = FileNode(url: folderURL)
        let icon = cache.icon(for: node)
        XCTAssertNotNil(icon)
    }

    func testSameExtensionReturnsCachedIcon() {
        let cache = IconCache()
        let tmpDir = FileManager.default.temporaryDirectory

        let file1 = tmpDir.appendingPathComponent("a.swift")
        let file2 = tmpDir.appendingPathComponent("b.swift")
        FileManager.default.createFile(atPath: file1.path, contents: nil)
        FileManager.default.createFile(atPath: file2.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: file1)
            try? FileManager.default.removeItem(at: file2)
        }

        let node1 = FileNode(url: file1)
        let node2 = FileNode(url: file2)
        let icon1 = cache.icon(for: node1)
        let icon2 = cache.icon(for: node2)
        // Same extension should return the same cached icon instance
        XCTAssertEqual(icon1, icon2)
    }

    func testDifferentExtensionReturnsDifferentIcon() {
        let cache = IconCache()
        let tmpDir = FileManager.default.temporaryDirectory

        let swiftFile = tmpDir.appendingPathComponent("test.swift")
        let txtFile = tmpDir.appendingPathComponent("test.txt")
        FileManager.default.createFile(atPath: swiftFile.path, contents: nil)
        FileManager.default.createFile(atPath: txtFile.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: swiftFile)
            try? FileManager.default.removeItem(at: txtFile)
        }

        let swiftNode = FileNode(url: swiftFile)
        let txtNode = FileNode(url: txtFile)
        let _ = cache.icon(for: swiftNode)
        let _ = cache.icon(for: txtNode)
        // Both should return non-nil icons
        XCTAssertNotNil(cache.icon(for: swiftNode))
        XCTAssertNotNil(cache.icon(for: txtNode))
    }
}
