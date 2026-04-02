import XCTest
@testable import Findery

final class FavoritesManagerTests: XCTestCase {

    func testSharedInstance() {
        let mgr = FavoritesManager.shared
        XCTAssertNotNil(mgr)
        XCTAssertFalse(mgr.favorites.isEmpty, "Should have default favorites")
    }

    func testAddAndRemove() {
        let mgr = FavoritesManager.shared
        let testURL = FileManager.default.temporaryDirectory.appendingPathComponent("findery-fav-test")
        try? FileManager.default.createDirectory(at: testURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testURL) }

        let countBefore = mgr.favorites.count
        mgr.add(testURL)
        XCTAssertTrue(mgr.contains(testURL))
        XCTAssertEqual(mgr.favorites.count, countBefore + 1)

        mgr.remove(url: testURL)
        XCTAssertFalse(mgr.contains(testURL))
        XCTAssertEqual(mgr.favorites.count, countBefore)
    }

    func testAddDuplicate() {
        let mgr = FavoritesManager.shared
        let url = mgr.favorites.first!
        let countBefore = mgr.favorites.count
        mgr.add(url)
        XCTAssertEqual(mgr.favorites.count, countBefore, "Duplicate should not be added")
    }

    func testIconForKnownFolders() {
        XCTAssertEqual(FavoritesManager.icon(for: URL(fileURLWithPath: "/Users/test/Desktop")), "desktopcomputer")
        XCTAssertEqual(FavoritesManager.icon(for: URL(fileURLWithPath: "/Users/test/Downloads")), "arrow.down.circle.fill")
        XCTAssertEqual(FavoritesManager.icon(for: URL(fileURLWithPath: "/Users/test/Documents")), "doc.fill")
        XCTAssertEqual(FavoritesManager.icon(for: URL(fileURLWithPath: "/some/random/folder")), "folder.fill")
    }
}
