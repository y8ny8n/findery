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
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Findery"
        window.minSize = NSSize(width: 600, height: 400)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "FinderyTab"

        super.init(window: window)
        setupSplitView()
        setupMenuShortcuts()
        setupFileWatcher()

        // 이전 윈도우 크기/위치 복원 (없으면 기본 1200x800)
        window.setFrameAutosaveName("FinderyMainWindow")
        if !window.setFrameUsingName("FinderyMainWindow") {
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let w: CGFloat = min(1200, screenFrame.width * 0.85)
                let h: CGFloat = min(800, screenFrame.height * 0.85)
                let x = screenFrame.origin.x + (screenFrame.width - w) / 2
                let y = screenFrame.origin.y + (screenFrame.height - h) / 2
                window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
            } else {
                window.setContentSize(NSSize(width: 1200, height: 800))
                window.center()
            }
        }
        setupNotifications()
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
        // Nav buttons use NotificationCenter (setupNotifications)

        fileListContainerVC.contextMenuProvider = { [weak self] urls in
            self?.buildContextMenu(for: urls) ?? NSMenu()
        }

        fileListContainerVC.onRenameComplete = { [weak self] original, renamed in
            self?.undoStack.append(.rename(original: original, renamed: renamed))
        }
        fileListContainerVC.onRenameBegan = { [weak self] in
            self?.fileWatcher.pause()
        }
        fileListContainerVC.onRenameEnded = { [weak self] in
            self?.fileWatcher.resume()
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

        let servicesMenu = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "서비스", action: nil, keyEquivalent: "")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Findery 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        let newWindowItem = NSMenuItem(title: "새 윈도우", action: #selector(AppDelegate.newWindow(_:)), keyEquivalent: "n")
        fileMenu.addItem(newWindowItem)
        let newTabItem = NSMenuItem(title: "새 탭", action: #selector(AppDelegate.newTab(_:)), keyEquivalent: "t")
        fileMenu.addItem(newTabItem)
        fileMenu.addItem(item("새 폴더", action: #selector(newFolderAction), key: "n", modifiers: [.command, .shift]))
        let compressMenuItem = NSMenuItem(title: "압축하기", action: #selector(compressSelectedAction), keyEquivalent: "c")
        compressMenuItem.keyEquivalentModifierMask = [.control, .shift]
        compressMenuItem.target = self
        fileMenu.addItem(compressMenuItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu — standard selectors (no target) so text fields handle ⌘C/⌘V/⌘A
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(item("실행 취소", action: #selector(undoAction), key: "z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenu.addItem(NSMenuItem.separator())

        // F2 is handled via keyDown in FileListContainerViewController (keyCode 120).
        // Menu item kept for discoverability only; no keyEquivalent set because
        // AppKit does not reliably match F2 through the menu dispatch system.
        let renameItem = NSMenuItem(title: "이름 변경 (F2)", action: #selector(renameAction), keyEquivalent: "")
        renameItem.target = self
        editMenu.addItem(renameItem)

        editMenu.addItem(NSMenuItem.separator())
        let trashItem = NSMenuItem(title: "휴지통으로 이동", action: #selector(moveToTrashAction), keyEquivalent: "\u{08}")
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
        viewMenu.addItem(item("검색", action: #selector(focusSearchAction), key: "f"))
        viewMenu.addItem(item("숨김파일 표시/숨기기", action: #selector(toggleHiddenAction), key: ".", modifiers: [.command, .shift]))
        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
    }

    private func setupNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(goBackAction), name: .finderyGoBack, object: nil)
        nc.addObserver(self, selector: #selector(goForwardAction), name: .finderyGoForward, object: nil)
        nc.addObserver(self, selector: #selector(goUpAction), name: .finderyGoUp, object: nil)
        nc.addObserver(self, selector: #selector(handleFileCopy(_:)), name: .finderyCopy, object: nil)
        nc.addObserver(self, selector: #selector(handleFileCut(_:)), name: .finderyCut, object: nil)
        nc.addObserver(self, selector: #selector(handleFilePaste), name: .finderyPaste, object: nil)
        nc.addObserver(self, selector: #selector(moveToTrashAction), name: .finderyMoveToTrash, object: nil)
        nc.addObserver(self, selector: #selector(handleToggleHidden(_:)), name: .finderyToggleHidden, object: nil)
    }

    @objc private func toggleHiddenAction() {
        fileListContainerVC.toggleHiddenFiles()
    }

    @objc private func handleToggleHidden(_ notification: Notification) {
        guard let show = notification.object as? Bool else { return }
        fileSystemController.showHiddenFiles = show
        treeSidebarVC.reloadTree()
        refreshCurrentDirectory()
    }

    @objc private func handleFileCopy(_ notification: Notification) {
        guard let urls = notification.object as? [URL], !urls.isEmpty else { return }
        clipboardURLs = urls
        clipboardIsCut = false
        fileOperations.copyToClipboard(urls: urls)
    }

    @objc private func handleFileCut(_ notification: Notification) {
        guard let urls = notification.object as? [URL], !urls.isEmpty else { return }
        clipboardURLs = urls
        clipboardIsCut = true
        clipboardSourceDir = currentURL
        fileOperations.copyToClipboard(urls: urls)
        fileListContainerVC.setCutURLs(Set(urls))
    }

    @objc private func handleFilePaste() {
        pasteAction()
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
            } else {
                let openItem = NSMenuItem(title: "열기", action: #selector(contextOpenFile(_:)), keyEquivalent: "")
                openItem.target = self
                openItem.representedObject = url
                menu.addItem(openItem)
            }

            // "다음으로 열기" 서브메뉴
            let openWithItem = NSMenuItem(title: "다음으로 열기", action: nil, keyEquivalent: "")
            let openWithMenu = NSMenu(title: "Open With")
            let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: url)
            for appURL in appURLs.prefix(15) {
                let appName = appURL.deletingPathExtension().lastPathComponent
                let appItem = NSMenuItem(title: appName, action: #selector(contextOpenWith(_:)), keyEquivalent: "")
                appItem.target = self
                appItem.representedObject = ["file": url, "app": appURL]
                appItem.image = NSWorkspace.shared.icon(forFile: appURL.path)
                appItem.image?.size = NSSize(width: 16, height: 16)
                openWithMenu.addItem(appItem)
            }
            openWithItem.submenu = openWithMenu
            menu.addItem(openWithItem)
            menu.addItem(NSMenuItem.separator())
        }

        // 여러 파일 선택 시에도 "다음으로 열기" 제공
        if urls.count > 1 {
            let openWithItem = NSMenuItem(title: "다음으로 열기", action: nil, keyEquivalent: "")
            let openWithMenu = NSMenu(title: "Open With")
            let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: urls[0])
            for appURL in appURLs.prefix(15) {
                let appName = appURL.deletingPathExtension().lastPathComponent
                let appItem = NSMenuItem(title: appName, action: #selector(contextOpenWithMulti(_:)), keyEquivalent: "")
                appItem.target = self
                appItem.representedObject = ["files": urls, "app": appURL]
                appItem.image = NSWorkspace.shared.icon(forFile: appURL.path)
                appItem.image?.size = NSSize(width: 16, height: 16)
                openWithMenu.addItem(appItem)
            }
            openWithItem.submenu = openWithMenu
            menu.addItem(openWithItem)
            menu.addItem(NSMenuItem.separator())
        }

        // 쓰기 가능 여부 확인
        let allWritable = urls.allSatisfy { url in
            FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
        }

        menu.addItem(withTitle: "복사", action: #selector(copyAction), keyEquivalent: "").target = self
        let cutItem = NSMenuItem(title: "잘라내기", action: allWritable ? #selector(cutAction) : nil, keyEquivalent: "")
        cutItem.target = self
        cutItem.isEnabled = allWritable
        menu.addItem(cutItem)

        if !clipboardURLs.isEmpty {
            let pasteTitle = clipboardIsCut ? "여기에 이동" : "여기에 붙여넣기"
            menu.addItem(withTitle: pasteTitle, action: #selector(pasteAction), keyEquivalent: "").target = self
        }

        menu.addItem(NSMenuItem.separator())
        let renameItem = NSMenuItem(title: "이름 변경", action: allWritable ? #selector(renameAction) : nil, keyEquivalent: "")
        renameItem.target = self
        renameItem.isEnabled = allWritable
        menu.addItem(renameItem)
        menu.addItem(NSMenuItem.separator())

        let trashItem = NSMenuItem(title: "휴지통으로 이동", action: allWritable ? #selector(moveToTrashAction) : nil, keyEquivalent: "")
        trashItem.target = self
        trashItem.isEnabled = allWritable
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

            // 폴더일 때 즐겨찾기 추가/제거
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                menu.addItem(NSMenuItem.separator())
                if FavoritesManager.shared.contains(url) {
                    let removeItem = NSMenuItem(title: "즐겨찾기에서 제거", action: #selector(contextRemoveFavorite(_:)), keyEquivalent: "")
                    removeItem.target = self
                    removeItem.representedObject = url
                    menu.addItem(removeItem)
                } else {
                    let addItem = NSMenuItem(title: "즐겨찾기에 추가", action: #selector(contextAddFavorite(_:)), keyEquivalent: "")
                    addItem.target = self
                    addItem.representedObject = url
                    menu.addItem(addItem)
                }
            }
        }

        menu.addItem(NSMenuItem.separator())

        // 압축하기
        let compressItem = NSMenuItem(title: "압축하기", action: #selector(contextCompress(_:)), keyEquivalent: "")
        compressItem.target = self
        compressItem.representedObject = urls
        menu.addItem(compressItem)

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
        fileListContainerVC.startRenaming()
    }

    @objc private func moveToTrashAction() {
        let urls = fileListContainerVC.selectedFileURLs
        guard !urls.isEmpty else { return }

        // 선택된 행 페이드아웃 애니메이션
        fileListContainerVC.animateRemovalOfSelected { [weak self] in
            guard let self else { return }
            do {
                let trashedPairs = try self.fileOperations.moveToTrashWithUndo(urls: urls)
                self.undoStack.append(.trash(trashedURLs: trashedPairs))
                // 휴지통 사운드
                NSSound(contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif", byReference: true)?.play()
                self.refreshCurrentDirectory()
            } catch {
                self.refreshCurrentDirectory()
                self.showError(error)
            }
        }
    }

    @objc private func undoAction() {
        guard let action = undoStack.popLast() else {
            NSSound.beep()
            return
        }

        var affectedURLs: [URL] = []

        do {
            switch action {
            case .copy(let created):
                for url in created {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }

            case .move(let pairs):
                for pair in pairs {
                    try FileManager.default.moveItem(at: pair.dest, to: pair.source)
                    affectedURLs.append(pair.source)
                }

            case .rename(let original, let renamed):
                try FileManager.default.moveItem(at: renamed, to: original)
                affectedURLs.append(original)

            case .trash(let trashedURLs):
                for pair in trashedURLs {
                    try FileManager.default.moveItem(at: pair.trashURL, to: pair.original)
                    affectedURLs.append(pair.original)
                }

            case .newFolder(let url):
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }

            refreshCurrentDirectory()

            // 되돌린 파일 하이라이트 + 깜빡임
            if !affectedURLs.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.fileListContainerVC.flashFiles(urls: affectedURLs)
                }
            }

            NSSound(named: .init("Funk"))?.play()
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

    @objc private func contextOpenWith(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let fileURL = info["file"] as? URL,
              let appURL = info["app"] as? URL else { return }
        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func contextOpenWithMulti(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let fileURLs = info["files"] as? [URL],
              let appURL = info["app"] as? URL else { return }
        NSWorkspace.shared.open(fileURLs, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func compressSelectedAction() {
        let urls = fileListContainerVC.selectedFileURLs
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }
        compressFiles(urls)
    }

    @objc private func contextCompress(_ sender: NSMenuItem) {
        guard let urls = sender.representedObject as? [URL], !urls.isEmpty else { return }
        compressFiles(urls)
    }

    private func compressFiles(_ urls: [URL]) {
        // Keka가 설치되어 있으면 Keka로 압축
        if let kekaURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.aone.keka") {
            NSWorkspace.shared.open(urls, withApplicationAt: kekaURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }

        // Keka 없으면 시스템 ditto로 zip 압축
        guard let destination = currentURL else { return }
        let zipName: String
        if urls.count == 1 {
            zipName = urls[0].deletingPathExtension().lastPathComponent + ".zip"
        } else {
            zipName = "압축.zip"
        }
        var zipURL = destination.appendingPathComponent(zipName)

        var counter = 2
        while FileManager.default.fileExists(atPath: zipURL.path) {
            let base = zipURL.deletingPathExtension().lastPathComponent
            let cleanBase = base.replacingOccurrences(of: " \\d+$", with: "", options: .regularExpression)
            zipURL = destination.appendingPathComponent("\(cleanBase) \(counter).zip")
            counter += 1
        }

        let filePaths = urls.map(\.path)
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc"] + filePaths + [zipURL.path]
            try? process.run()
            process.waitUntilExit()
        }
    }

    @objc private func contextAddFavorite(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        FavoritesManager.shared.add(url)
    }

    @objc private func contextRemoveFavorite(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        FavoritesManager.shared.remove(url: url)
    }

    @objc private func focusSearchAction() {
        fileListContainerVC.focusSearch()
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
