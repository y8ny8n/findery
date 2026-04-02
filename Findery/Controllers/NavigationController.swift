import Foundation

final class NavigationController {
    let state = NavigationState()

    func navigate(to url: URL) {
        state.navigate(to: url)
    }

    func goBack() -> URL? {
        state.goBack()
    }

    func goForward() -> URL? {
        state.goForward()
    }

    func goUp() -> URL? {
        state.goUp()
    }
}
