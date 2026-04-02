import XCTest
@testable import Findery

final class NavigationStateTests: XCTestCase {

    private var state: NavigationState!
    private let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
    private let desktop = URL(fileURLWithPath: "/Users/test/Desktop", isDirectory: true)
    private let documents = URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)

    override func setUp() {
        super.setUp()
        state = NavigationState()
    }

    func testInitialState() {
        XCTAssertNil(state.currentURL)
        XCTAssertFalse(state.canGoBack)
        XCTAssertFalse(state.canGoForward)
    }

    func testNavigate() {
        state.navigate(to: home)
        XCTAssertEqual(state.currentURL, home)
        XCTAssertFalse(state.canGoBack)

        state.navigate(to: desktop)
        XCTAssertEqual(state.currentURL, desktop)
        XCTAssertTrue(state.canGoBack)
        XCTAssertFalse(state.canGoForward)
    }

    func testGoBack() {
        state.navigate(to: home)
        state.navigate(to: desktop)

        let result = state.goBack()
        XCTAssertEqual(result, home)
        XCTAssertEqual(state.currentURL, home)
        XCTAssertTrue(state.canGoForward)
        XCTAssertFalse(state.canGoBack)
    }

    func testGoForward() {
        state.navigate(to: home)
        state.navigate(to: desktop)
        _ = state.goBack()

        let result = state.goForward()
        XCTAssertEqual(result, desktop)
        XCTAssertEqual(state.currentURL, desktop)
    }

    func testNavigateClearsForwardStack() {
        state.navigate(to: home)
        state.navigate(to: desktop)
        _ = state.goBack()
        XCTAssertTrue(state.canGoForward)

        state.navigate(to: documents)
        XCTAssertFalse(state.canGoForward)
    }

    func testGoBackOnEmptyReturnsNil() {
        XCTAssertNil(state.goBack())
    }

    func testGoForwardOnEmptyReturnsNil() {
        XCTAssertNil(state.goForward())
    }

    func testGoUp() {
        state.navigate(to: desktop)
        let parent = state.goUp()
        XCTAssertEqual(parent?.standardizedFileURL, home.standardizedFileURL)
        XCTAssertEqual(state.currentURL?.standardizedFileURL, home.standardizedFileURL)
        XCTAssertTrue(state.canGoBack)
    }

    func testGoUpAtRootReturnsNil() {
        state.navigate(to: URL(fileURLWithPath: "/"))
        XCTAssertNil(state.goUp())
    }
}
