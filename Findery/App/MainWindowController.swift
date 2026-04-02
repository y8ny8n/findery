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
    private var clipboardURLs: [URL] = []
    private var clipboardIsCut = false
    private var clipboardSourceDir: URL?
    private var undoStack: [UndoableAction] = []

    enum UndoableAction {
        case copy(created: [URL])
        case move(from: [(source: URL, dest: URL)])
        case rename(original: URL, renamed: URL)
        case trash(trashedURLs: [(original: URL, trashURL: URL)])
        case newFolder(url: URL)
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
        fileListContainerVC.onGoBack = { [weak self] in self?.goBackAction() }
        fileListContainerVC.onGoForward = { [weak self] in self?.goForwardAction() }
        fileListContainerVC.onGoUp = { [weak self] in self?.goUpAction() }

        fileListContainerVC.contextMenuProvider = { [weak self] urls in
            self?.buildContextMenu(for: urls) ?? NSMenu()
        }
    }

    private func setupMenuShortcuts() {
        let mainMenu = NSMenu(title: "MainMenu")
        NSApp.mainMenu = mainMenu

        func item(_ title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
            mi.keyEquivalentModifierMask = modifiers
            mi.target = self
            return mi
        }

        // App menu
        let appMenu = NSMenu(title: "Findery")
        appMenu.addItem(withTitle: "Findery에 관하여", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Findery 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item("새 폴더", action: #selector(newFolderAction), key: "n", modifiers: [.command, .shift]))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(item("실행 취소", action: #selector(undoAction), key: "z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(item("잘라내기", action: #selector(cutAction), key: "x"))
        editMenu.addItem(item("복사", action: #selector(copyAction), key: "c"))
        editMenu.addItem(item("붙여넣기", action: #selector(pasteAction), key: "v"))
        editMenu.addItem(NSMenuItem.separator())

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

        // View menu
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(item("새로고침", action: #selector(refreshAction), key: "r"))
        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
    }

    private func setupFileWatcher() {
        fileWatcher.onChange = { [weak self] in
            self?.refreshCurrentDirectory()
        }
    }

    // MARK: - Context Menu

    private func buildContextMenu(for urls: [URL]) -> NSMenu {
        let menu = NSMenu()

        if urls.isEmpty {
            menu.addItem(withTitle: "새 폴더", action: #selector(newFolderAction), keyEquivalent: "").target = self
            menu.addItem(NSMenuItem.separator())
            if !clipboardURLs.isEmpty {
                let pasteTitle = clipboardIsCut ? "여기에 이동" : "여기에 붙여넣기"
                menu.addItem(withTitle: pasteTitle, action: #selector(pasteAction), keyEquivalent: "").target = self
            }
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "새로고침", action: #selector(refreshAction), keyEquivalent: "").target = self
            return menu
        }

        if urls.count == 1, let url = urls.first {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let openItem = NSMenuItem(title: "열기", action: #selector(contextOpenFolder(_:)), keyEquivalent: "")
                openItem.target = self
                openItem.representedObject = url
                menu.addItem(openItem)
                menu.addItem(NSMenuItem.separator())
            } else {
                let openItem = NSMenuItem(title: "열기", action: #selector(contextOpenFile(_:)), keyEquivalent: "")
                openItem.target = self
                openItem.representedObject = url
                menu.addItem(openItem)
                menu.addItem(NSMenuItem.separator())
            }
        }

        menu.addItem(withTitle: "복사", action: #selector(copyAction), keyEquivalent: "").target = self
        let cutItem = NSMenuItem(title: "잘라내기", action: #selector(cutAction), keyEquivalent: "")
        cutItem.target = self
        menu.addItem(cutItem)

        if !clipboardURLs.isEmpty {
            let pasteTitle = clipboardIsCut ? "여기에 이동" : "여기에 붙여넣기"
            menu.addItem(withTitle: pasteTitle, action: #selector(pasteAction), keyEquivalent: "").target = self
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "이름 변경", action: #selector(renameAction), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())

        let trashItem = NSMenuItem(title: "휴지통으로 이동", action: #selector(moveToTrashAction), keyEquivalent: "")
        trashItem.target = self
        menu.addItem(trashItem)

        menu.addItem(NSMenuItem.separator())

        if urls.count == 1, let url = urls.first {
            let revealItem = NSMenuItem(title: "Finder에서 보기", action: #selector(contextRevealInFinder(_:)), keyEquivalent: "")
            revealItem.target = self
            revealItem.representedObject = url
            menu.addItem(revealItem)

            let infoItem = NSMenuItem(title: "정보 가져오기", action: #selector(contextGetInfo(_:)), keyEquivalent: "")
            infoItem.target = self
            infoItem.representedObject = url
            menu.addItem(infoItem)
        }

        return menu
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
            updateNavButtonStates()
        }
    }

    private func updateNavButtonStates() {
        fileListContainerVC.updateNavButtons(
            canGoBack: navigationController.state.canGoBack,
            canGoForward: navigationController.state.canGoForward
        )
    }

    private func refreshCurrentDirectory() {
        guard let url = currentURL else { return }
        Task { @MainActor in
            let items = await fileSystemController.enumerate(directory: url)
            fileListContainerVC.updateFiles(items, iconCache: iconCache)
        }
    }

    // MARK: - Navigation Actions

    @objc private func goBackAction() {
        guard let url = navigationController.goBack() else { return }
        navigateWithoutPush(url)
    }

    @objc private func goForwardAction() {
        guard let url = navigationController.goForward() else { return }
        navigateWithoutPush(url)
    }

    @objc private func goUpAction() {
        guard let url = navigationController.goUp() else { return }
        navigateWithoutPush(url)
    }

    private func navigateWithoutPush(_ url: URL) {
        currentURL = url
        fileWatcher.watch(directory: url)
        Task { @MainActor in
            let items = await fileSystemController.enumerate(directory: url)
            fileListContainerVC.updateFiles(items, iconCache: iconCache)
            fileListContainerVC.updateAddressBar(url)
            treeSidebarVC.selectDirectory(url)
            updateNavButtonStates()
        }
    }

    @objc private func focusAddressBar() {
        fileListContainerVC.focusAddressBar()
    }

    // MARK: - File Actions

    @objc private func newFolderAction() {
        guard let url = currentURL else { return }
        do {
            let folderURL = try fileOperations.createNewFolder(in: url)
            undoStack.append(.newFolder(url: folderURL))
            refreshCurrentDirectory()
        } catch {
            showError(error)
        }
    }

    @objc private func renameAction() {
        fileListContainerVC.onRenameComplete = { [weak self] original, renamed in
            self?.undoStack.append(.rename(original: original, renamed: renamed))
        }
        fileListContainerVC.startRenaming()
    }

    @objc private func moveToTrashAction() {
        let urls = fileListContainerVC.selectedFileURLs
        guard !urls.isEmpty else { return }
        do {
            let trashedPairs = try fileOperations.moveToTrashWithUndo(urls: urls)
            undoStack.append(.trash(trashedURLs: trashedPairs))
            refreshCurrentDirectory()
        } catch {
            showError(error)
        }
    }

    @objc private func undoAction() {
        guard let action = undoStack.popLast() else {
            NSSound.beep()
            return
        }

        do {
            switch action {
            case .copy(let created):
                for url in created {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }

            case .move(let pairs):
                for pair in pairs {
                    try FileManager.default.moveItem(at: pair.dest, to: pair.source)
                }

            case .rename(let original, let renamed):
                try FileManager.default.moveItem(at: renamed, to: original)

            case .trash(let trashedURLs):
                for pair in trashedURLs {
                    try FileManager.default.moveItem(at: pair.trashURL, to: pair.original)
                }

            case .newFolder(let url):
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
            refreshCurrentDirectory()
        } catch {
            showError(error)
        }
    }

    // MARK: - Copy / Cut / Paste

    @objc private func copyAction() {
        let urls = fileListContainerVC.selectedFileURLs
        guard !urls.isEmpty else { return }
        clipboardURLs = urls
        clipboardIsCut = false
        fileOperations.copyToClipboard(urls: urls)
    }

    @objc private func cutAction() {
        let urls = fileListContainerVC.selectedFileURLs
        guard !urls.isEmpty else { return }
        clipboardURLs = urls
        clipboardIsCut = true
        clipboardSourceDir = currentURL
        fileOperations.copyToClipboard(urls: urls)
        fileListContainerVC.setCutURLs(Set(urls))
    }

    @objc private func pasteAction() {
        guard let destination = currentURL, !clipboardURLs.isEmpty else { return }
        let sourceDir = clipboardSourceDir
        do {
            if clipboardIsCut {
                let pairs = try fileOperations.moveFilesWithUndo(clipboardURLs, to: destination)
                undoStack.append(.move(from: pairs))
                clipboardURLs = []
                clipboardIsCut = false
                fileListContainerVC.setCutURLs([])
                // 원래 폴더가 현재 폴더와 다르면 현재 폴더 리프레시
                // 원래 폴더가 현재 폴더면 FSEvents가 잡아줌
                if sourceDir != destination {
                    refreshCurrentDirectory()
                }
            } else {
                let created = try fileOperations.copyFilesWithUndo(clipboardURLs, to: destination)
                undoStack.append(.copy(created: created))
            }
            refreshCurrentDirectory()
        } catch {
            showError(error)
        }
    }

    @objc private func moveAction() {
        guard let destination = currentURL, !clipboardURLs.isEmpty else { return }
        do {
            let pairs = try fileOperations.moveFilesWithUndo(clipboardURLs, to: destination)
            undoStack.append(.move(from: pairs))
            clipboardURLs = []
            clipboardIsCut = false
            refreshCurrentDirectory()
        } catch {
            showError(error)
        }
    }

    // MARK: - Context Menu Actions

    @objc private func contextOpenFolder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        navigateTo(url)
    }

    @objc private func contextOpenFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        fileOperations.openFile(url)
    }

    @objc private func contextRevealInFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func contextGetInfo(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
