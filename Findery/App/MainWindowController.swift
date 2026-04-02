import AppKit

final class MainWindowController: NSWindowController, NSToolbarDelegate {

    private let splitViewController = NSSplitViewController()
    private let treeSidebarVC = TreeSidebarViewController()
    private let fileListContainerVC = FileListContainerViewController()

    private let navigationController = NavigationController()
    private let fileSystemController = FileSystemController()
    private let fileOperations = FileOperations()
    private let iconCache = IconCache()
    private let fileWatcher = FileWatcher()

    private var currentURL: URL?

    // MARK: - Toolbar item identifiers

    private enum ToolbarItem: String {
        case navigation = "NavigationItem"
        case addressBar = "AddressBarItem"
    }

    // MARK: - Init

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
        setupMenuShortcuts()
        setupFileWatcher()
        navigateTo(FileSystemController.homeDirectory)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

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

        fileListContainerVC.onNavigate = { [weak self] url in
            self?.navigateTo(url)
        }
    }

    private func setupMenuShortcuts() {
        guard let mainMenu = NSApp.mainMenu else { return }

        // Helper to create menu items with self as target
        func item(_ title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
            mi.keyEquivalentModifierMask = modifiers
            mi.target = self
            return mi
        }

        // File menu
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item("새 폴더", action: #selector(newFolderAction), key: "n", modifiers: [.command, .shift]))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Go menu
        let goMenu = NSMenu(title: "Go")
        goMenu.addItem(item("뒤로", action: #selector(goBackAction), key: "["))
        goMenu.addItem(item("앞으로", action: #selector(goForwardAction), key: "]"))

        let goUpItem = NSMenuItem(title: "상위 폴더", action: #selector(goUpAction), keyEquivalent: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)))
        goUpItem.keyEquivalentModifierMask = .command
        goUpItem.target = self
        goMenu.addItem(goUpItem)

        goMenu.addItem(NSMenuItem.separator())
        goMenu.addItem(item("주소창으로 이동", action: #selector(focusAddressBar), key: "l"))

        let goMenuItem = NSMenuItem(title: "Go", action: nil, keyEquivalent: "")
        goMenuItem.submenu = goMenu
        mainMenu.addItem(goMenuItem)

        // Edit menu (rename, trash)
        let editMenu = NSMenu(title: "Edit")
        let renameItem = NSMenuItem(title: "이름 변경", action: #selector(renameAction), keyEquivalent: "")
        renameItem.keyEquivalent = String(Character(UnicodeScalar(NSF2FunctionKey)!))
        renameItem.keyEquivalentModifierMask = []
        renameItem.target = self
        editMenu.addItem(renameItem)

        editMenu.addItem(NSMenuItem.separator())
        let trashItem = NSMenuItem(title: "휴지통으로 이동", action: #selector(moveToTrashAction), keyEquivalent: String(Character(UnicodeScalar(NSBackspaceCharacter)!)))
        trashItem.keyEquivalentModifierMask = .command
        trashItem.target = self
        editMenu.addItem(trashItem)

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu (refresh)
        let viewMenu = NSMenu(title: "View")
        let refreshItem = item("새로고침", action: #selector(refreshAction), key: "r")
        viewMenu.addItem(refreshItem)

        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
    }

    private func setupFileWatcher() {
        fileWatcher.onChange = { [weak self] in
            self?.refreshCurrentDirectory()
        }
    }

    // MARK: - Navigation

    func navigateTo(_ url: URL) {
        currentURL = url
        navigationController.navigate(to: url)
        fileWatcher.watch(directory: url)

        Task { @MainActor in
            let items = await fileSystemController.enumerate(directory: url)
            fileListContainerVC.updateFiles(items, iconCache: iconCache)
            fileListContainerVC.updateAddressBar(url)
            treeSidebarVC.selectDirectory(url)
        }
    }

    private func refreshCurrentDirectory() {
        guard let url = currentURL else { return }
        Task { @MainActor in
            let items = await fileSystemController.enumerate(directory: url)
            fileListContainerVC.updateFiles(items, iconCache: iconCache)
        }
    }

    // MARK: - Actions

    @objc private func goBackAction() {
        guard let url = navigationController.goBack() else { return }
        currentURL = url
        fileWatcher.watch(directory: url)
        Task { @MainActor in
            let items = await fileSystemController.enumerate(directory: url)
            fileListContainerVC.updateFiles(items, iconCache: iconCache)
            fileListContainerVC.updateAddressBar(url)
            treeSidebarVC.selectDirectory(url)
        }
    }

    @objc private func goForwardAction() {
        guard let url = navigationController.goForward() else { return }
        currentURL = url
        fileWatcher.watch(directory: url)
        Task { @MainActor in
            let items = await fileSystemController.enumerate(directory: url)
            fileListContainerVC.updateFiles(items, iconCache: iconCache)
            fileListContainerVC.updateAddressBar(url)
            treeSidebarVC.selectDirectory(url)
        }
    }

    @objc private func goUpAction() {
        guard let url = navigationController.goUp() else { return }
        currentURL = url
        fileWatcher.watch(directory: url)
        Task { @MainActor in
            let items = await fileSystemController.enumerate(directory: url)
            fileListContainerVC.updateFiles(items, iconCache: iconCache)
            fileListContainerVC.updateAddressBar(url)
            treeSidebarVC.selectDirectory(url)
        }
    }

    @objc private func focusAddressBar() {
        fileListContainerVC.focusAddressBar()
    }

    @objc private func newFolderAction() {
        guard let url = currentURL else { return }
        do {
            _ = try fileOperations.createNewFolder(in: url)
        } catch {
            showError(error)
        }
    }

    @objc private func renameAction() {
        fileListContainerVC.startRenaming()
    }

    @objc private func moveToTrashAction() {
        let urls = fileListContainerVC.selectedFileURLs
        guard !urls.isEmpty else { return }
        do {
            try fileOperations.moveToTrash(urls: urls)
        } catch {
            showError(error)
        }
    }

    @objc private func refreshAction() {
        refreshCurrentDirectory()
    }

    private func showError(_ error: Error) {
        guard let window else { return }
        let alert = NSAlert(error: error)
        alert.beginSheetModal(for: window)
    }
}

// MARK: - TreeSidebarDelegate
extension MainWindowController: TreeSidebarDelegate {
    func treeSidebar(_ sidebar: TreeSidebarViewController, didSelectDirectory url: URL) {
        navigateTo(url)
    }
}
