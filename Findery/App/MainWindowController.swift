import AppKit

final class MainWindowController: NSWindowController {

    private let splitViewController = NSSplitViewController()
    private let treeSidebarVC = TreeSidebarViewController()
    private let fileListContainerVC = FileListContainerViewController()

    private let navigationController = NavigationController()
    private let fileSystemController = FileSystemController()
    private let iconCache = IconCache()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Findery"
        window.minSize = NSSize(width: 600, height: 400)
        window.center()

        super.init(window: window)
        setupSplitView()
        setupToolbar()
        navigateTo(FileSystemController.homeDirectory)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSplitView() {
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: treeSidebarVC)
        sidebarItem.minimumThickness = 150
        sidebarItem.maximumThickness = 400

        let contentItem = NSSplitViewItem(viewController: fileListContainerVC)
        contentItem.minimumThickness = 300

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(contentItem)

        window?.contentViewController = splitViewController

        treeSidebarVC.delegate = self
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar
    }

    func navigateTo(_ url: URL) {
        navigationController.navigate(to: url)

        Task { @MainActor in
            let items = await fileSystemController.enumerate(directory: url)
            fileListContainerVC.updateFiles(items, iconCache: iconCache)
            fileListContainerVC.updateAddressBar(url)
            treeSidebarVC.selectDirectory(url)
        }
    }
}

extension MainWindowController: TreeSidebarDelegate {
    func treeSidebar(_ sidebar: TreeSidebarViewController, didSelectDirectory url: URL) {
        navigateTo(url)
    }
}
