import XCTest
@testable import Findery

final class FileSystemControllerTests: XCTestCase {

    private var controller: FileSystemController!

    override func setUp() {
        super.setUp()
        controller = FileSystemController()
    }

    func testExpandTildeHome() {
        let result = FileSystemController.expandTilde("~")
        XCTAssertNotNil(result)
        XCTAssertEqual(result, FileSystemController.homeDirectory)
    }

    func testExpandTildeDesktop() {
        let result = FileSystemController.expandTilde("~/Desktop")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.path.hasSuffix("/Desktop"))
    }

    func testExpandTildeInvalidPath() {
        let result = FileSystemController.expandTilde("~/nonexistent_dir_12345")
        XCTAssertNil(result)
    }

    func testExpandAbsolutePath() {
        let result = FileSystemController.expandTilde("/tmp")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.path, "/tmp")
    }

    func testExpandEmptyString() {
        let result = FileSystemController.expandTilde("")
        XCTAssertNil(result)
    }

    func testEnumerateHomeDirectory() async {
        let items = await controller.enumerate(directory: FileSystemController.homeDirectory)
        XCTAssertFalse(items.isEmpty)
    }

    func testEnumerateDirectoriesFirst() async {
        let items = await controller.enumerate(directory: FileSystemController.homeDirectory)
        guard items.count >= 2 else { return }

        let firstNonDir = items.firstIndex { !$0.isDirectory }
        let lastDir = items.lastIndex { $0.isDirectory }

        if let firstNonDir, let lastDir {
            XCTAssertLessThan(lastDir, firstNonDir, "Directories should be sorted before files")
        }
    }
}
