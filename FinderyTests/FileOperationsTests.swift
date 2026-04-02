import XCTest
@testable import Findery

final class FileOperationsTests: XCTestCase {

    private var ops: FileOperations!
    private var testDir: URL!

    override func setUp() {
        super.setUp()
        ops = FileOperations()
        testDir = FileManager.default.temporaryDirectory.appendingPathComponent("findery-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testDir)
        super.tearDown()
    }

    // MARK: - Rename

    func testRenameFile() throws {
        let file = testDir.appendingPathComponent("old.txt")
        FileManager.default.createFile(atPath: file.path, contents: nil)

        let newURL = try ops.rename(at: file, to: "new.txt")
        XCTAssertEqual(newURL.lastPathComponent, "new.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRenameAlreadyExistsThrows() {
        let file1 = testDir.appendingPathComponent("a.txt")
        let file2 = testDir.appendingPathComponent("b.txt")
        FileManager.default.createFile(atPath: file1.path, contents: nil)
        FileManager.default.createFile(atPath: file2.path, contents: nil)

        XCTAssertThrowsError(try ops.rename(at: file1, to: "b.txt"))
    }

    // MARK: - New Folder

    func testCreateNewFolder() throws {
        let folder = try ops.createNewFolder(in: testDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(folder.lastPathComponent, "새 폴더")
    }

    func testCreateNewFolderAutoIncrement() throws {
        _ = try ops.createNewFolder(in: testDir)
        let folder2 = try ops.createNewFolder(in: testDir)
        XCTAssertEqual(folder2.lastPathComponent, "새 폴더 2")
    }

    // MARK: - Trash

    func testMoveToTrashWithUndo() throws {
        let file = testDir.appendingPathComponent("trash-me.txt")
        FileManager.default.createFile(atPath: file.path, contents: nil)

        let pairs = try ops.moveToTrashWithUndo(urls: [file])
        XCTAssertEqual(pairs.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        // Restore
        try FileManager.default.moveItem(at: pairs[0].trashURL, to: pairs[0].original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - Copy

    func testCopyFiles() throws {
        let file = testDir.appendingPathComponent("source.txt")
        FileManager.default.createFile(atPath: file.path, contents: "hello".data(using: .utf8))
        let destDir = testDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        try ops.copyFiles([file], to: destDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("source.txt").path))
    }

    func testCopyFilesWithUndoReturnsPaths() throws {
        let file = testDir.appendingPathComponent("src.txt")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let destDir = testDir.appendingPathComponent("dst")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let created = try ops.copyFilesWithUndo([file], to: destDir)
        XCTAssertEqual(created.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: created[0].path))
    }

    // MARK: - Move

    func testMoveFilesWithUndo() throws {
        let file = testDir.appendingPathComponent("move-me.txt")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let destDir = testDir.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let pairs = try ops.moveFilesWithUndo([file], to: destDir)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pairs[0].dest.path))
    }
}
