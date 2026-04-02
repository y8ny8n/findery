import Foundation

final class NavigationState {
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    private(set) var currentURL: URL?

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func navigate(to url: URL) {
        if let current = currentURL {
            backStack.append(current)
        }
        forwardStack.removeAll()
        currentURL = url
    }

    func goBack() -> URL? {
        guard let previous = backStack.popLast(), let current = currentURL else {
            return nil
        }
        forwardStack.append(current)
        currentURL = previous
        return previous
    }

    func goForward() -> URL? {
        guard let next = forwardStack.popLast(), let current = currentURL else {
            return nil
        }
        backStack.append(current)
        currentURL = next
        return next
    }

    func goUp() -> URL? {
        guard let current = currentURL else { return nil }
        let parent = current.deletingLastPathComponent().standardizedFileURL
        guard parent != current.standardizedFileURL else { return nil }
        navigate(to: parent)
        return parent
    }
}
