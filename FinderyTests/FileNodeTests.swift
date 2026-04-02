import XCTest
@testable import Findery

final class FileNodeTests: XCTestCase {

    func testRegularFile() {
        let url = FileSystemController.homeDirectory
            .appendingPathComponent("Desktop")
        let node = FileNode(url: url)
        XCTAssertEqual(node.name, "Desktop")
        XCTAssertTrue(node.isDirectory)
        XCTAssertFalse(node.isSymlink)
    }

    func testFormattedSizeForDirectory() {
        let url = FileSystemController.homeDirectory
        let node = FileNode(url: url)
        XCTAssertEqual(node.formattedSize, "--")
    }

    func testFormattedSizeForFile() {
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("findery-test-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: tmpFile.path, contents: Data(repeating: 0, count: 1024))
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let node = FileNode(url: tmpFile)
        XCTAssertFalse(node.isDirectory)
        XCTAssertFalse(node.formattedSize.isEmpty)
        XCTAssertNotEqual(node.formattedSize, "--")
    }

    func testFileExtension() {
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("test.swift")
        FileManager.default.createFile(atPath: tmpFile.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let node = FileNode(url: tmpFile)
        XCTAssertEqual(node.fileExtension, "swift")
    }

    func testNonExistentFile() {
        let url = URL(fileURLWithPath: "/nonexistent_path_12345/file.txt")
        let node = FileNode(url: url)
        XCTAssertEqual(node.name, "file.txt")
        XCTAssertFalse(node.isDirectory)
    }

    func testSymlinkDetection() {
        let tmpURL = URL(fileURLWithPath: "/tmp")
        let node = FileNode(url: tmpURL)
        // /tmp is a symlink to /private/tmp on macOS
        XCTAssertTrue(node.isSymlink)
        XCTAssertTrue(node.isDirectory)
    }

    func testWritableInHomeSubfolder() {
        let desktop = FileSystemController.homeDirectory.appendingPathComponent("Desktop")
        guard FileManager.default.fileExists(atPath: desktop.path) else { return }

        let tmpFile = desktop.appendingPathComponent("findery-test-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: tmpFile.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let node = FileNode(url: tmpFile)
        XCTAssertTrue(node.isWritable)
    }

    func testProtectedHomeFolderNotWritable() {
        let docs = FileSystemController.homeDirectory.appendingPathComponent("Documents")
        let node = FileNode(url: docs)
        XCTAssertFalse(node.isWritable, "Documents should be marked as protected")
    }
}
