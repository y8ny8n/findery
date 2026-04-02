import AppKit
import QuickLookUI

// MARK: - Rounded Row View (Finder-style)

private final class RoundedRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let inset = NSRect(x: bounds.minX + 4, y: bounds.minY + 1,
                           width: bounds.width - 8, height: bounds.height - 2)
        let path = NSBezierPath(roundedRect: inset, xRadius: 6, yRadius: 6)
        NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
        path.fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

// MARK: - Services-aware TableView

private final class ServicesTableView: NSTableView {

    var fileURLsProvider: (() -> [URL])?

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        let validSend = sendType == nil || sendType == .fileURL || sendType == .string
        let validReturn = returnType == nil
        if validSend && validReturn {
            if let urls = fileURLsProvider?(), !urls.isEmpty {
                return self
            }
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    @objc func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let urls = fileURLsProvider?(), !urls.isEmpty else { return false }
        pboard.clearContents()
        pboard.writeObjects(urls as [NSURL])
        pboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        return true
    }
}

final class FileListContainerViewController: NSViewController {

    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let upButton = NSButton()
    private let favoriteButton = NSButton()
    private let hiddenToggle = NSButton()
    private let addressBar = AddressBarView()
    private let searchField = NSSearchField()
    private(set) var showHiddenFiles = false
    private var currentURL: URL?
    private let tableView = ServicesTableView()
    private let scrollView = NSScrollView()
    private let statusBar = StatusBarView()

    private var allFiles: [FileNode] = []
    private var files: [FileNode] = []
    private var iconCache: IconCache?
    private var sortKey: SortKey = .name
    private var sortAscending = true

    var onNavigate: ((URL) -> Void)?
    var contextMenuProvider: (([URL]) -> NSMenu)?
    var onRenameComplete: ((URL, URL) -> Void)?
    var onGoBack: (() -> Void)?
    var onGoForward: (() -> Void)?
    var onRenameBegan: (() -> Void)?
    var onRenameEnded: (() -> Void)?
    var onGoUp: (() -> Void)?
    private var cutURLs: Set<URL> = []

    func setCutURLs(_ urls: Set<URL>) {
        cutURLs = urls
        tableView.reloadData()
    }

    func updateNavButtons(canGoBack: Bool, canGoForward: Bool) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
    }

    enum SortKey: String {
        case name, size, date, kind
    }

    override func loadView() {
        view = NSView()
        setupNavAndAddressBar()
        setupSearchBar()
        setupTableView()
        setupStatusBar()
    }

    private func setupNavAndAddressBar() {
        func makeNavButton(_ button: NSButton, symbol: String, action: Selector, tooltip: String) {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.bezelStyle = .accessoryBarAction
            button.isBordered = true
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = action
            button.toolTip = tooltip
            button.isEnabled = false
            view.addSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 28),
                button.heightAnchor.constraint(equalToConstant: 28),
            ])
        }

        makeNavButton(backButton, symbol: "chevron.left", action: #selector(backTapped), tooltip: "뒤로 (⌘[)")
        makeNavButton(forwardButton, symbol: "chevron.right", action: #selector(forwardTapped), tooltip: "앞으로 (⌘])")
        makeNavButton(upButton, symbol: "chevron.up", action: #selector(upTapped), tooltip: "상위 폴더 (⌘↑)")
        upButton.isEnabled = true

        // 즐겨찾기 버튼 (★)
        favoriteButton.translatesAutoresizingMaskIntoConstraints = false
        favoriteButton.bezelStyle = .accessoryBarAction
        favoriteButton.isBordered = true
        favoriteButton.image = NSImage(systemSymbolName: "star", accessibilityDescription: "즐겨찾기")
        favoriteButton.imageScaling = .scaleProportionallyDown
        favoriteButton.target = self
        favoriteButton.action = #selector(toggleFavorite)
        favoriteButton.toolTip = "즐겨찾기 추가/제거"
        favoriteButton.contentTintColor = .secondaryLabelColor
        view.addSubview(favoriteButton)

        // 숨김파일 토글 버튼 (.* 텍스트)
        hiddenToggle.translatesAutoresizingMaskIntoConstraints = false
        hiddenToggle.bezelStyle = .accessoryBarAction
        hiddenToggle.isBordered = true
        hiddenToggle.title = ".*"
        hiddenToggle.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        hiddenToggle.target = self
        hiddenToggle.action = #selector(toggleHiddenFiles)
        hiddenToggle.toolTip = "숨김파일 표시/숨기기 (⌘⇧.)"
        hiddenToggle.contentTintColor = .secondaryLabelColor
        view.addSubview(hiddenToggle)

        addressBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addressBar)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),

            forwardButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2),

            upButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            upButton.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 2),

            addressBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            addressBar.leadingAnchor.constraint(equalTo: upButton.trailingAnchor, constant: 8),
            addressBar.trailingAnchor.constraint(equalTo: favoriteButton.leadingAnchor, constant: -8),
            addressBar.heightAnchor.constraint(equalToConstant: 28),

            favoriteButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            favoriteButton.trailingAnchor.constraint(equalTo: hiddenToggle.leadingAnchor, constant: -2),
            favoriteButton.widthAnchor.constraint(equalToConstant: 28),
            favoriteButton.heightAnchor.constraint(equalToConstant: 28),

            hiddenToggle.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            hiddenToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            hiddenToggle.widthAnchor.constraint(equalToConstant: 28),
            hiddenToggle.heightAnchor.constraint(equalToConstant: 28),
        ])

        addressBar.onNavigate = { [weak self] url in
            self?.onNavigate?(url)
        }
    }

    @objc private func backTapped() {
        NotificationCenter.default.post(name: .finderyGoBack, object: nil)
    }
    @objc private func forwardTapped() {
        NotificationCenter.default.post(name: .finderyGoForward, object: nil)
    }
    @objc private func upTapped() {
        NotificationCenter.default.post(name: .finderyGoUp, object: nil)
    }
    @objc private func toggleFavorite() {
        guard let url = currentURL else { return }
        if FavoritesManager.shared.contains(url) {
            FavoritesManager.shared.remove(url: url)
        } else {
            FavoritesManager.shared.add(url)
        }
        updateFavoriteButton()
    }

    private func updateFavoriteButton() {
        guard let url = currentURL else { return }
        let isFav = FavoritesManager.shared.contains(url)
        favoriteButton.image = NSImage(systemSymbolName: isFav ? "star.fill" : "star",
                                        accessibilityDescription: "즐겨찾기")
        favoriteButton.contentTintColor = isFav ? .systemYellow : .secondaryLabelColor
    }

    @objc func toggleHiddenFiles() {
        showHiddenFiles.toggle()
        hiddenToggle.contentTintColor = showHiddenFiles ? .controlAccentColor : .secondaryLabelColor
        NotificationCenter.default.post(name: .finderyToggleHidden, object: showHiddenFiles)
    }

    private func setupSearchBar() {
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "검색 (⌘F)"
        searchField.font = NSFont.systemFont(ofSize: 12)
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        view.addSubview(searchField)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: addressBar.bottomAnchor, constant: 6),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            searchField.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @objc private func searchChanged() {
        let query = searchField.stringValue.lowercased()
        if query.isEmpty {
            files = allFiles
        } else {
            files = allFiles.filter { $0.name.lowercased().contains(query) }
        }
        tableView.reloadData()
        statusBar.update(itemCount: files.count, totalSize: files.reduce(0) { $0 + $1.size })
    }

    func focusSearch() {
        view.window?.makeFirstResponder(searchField)
    }

    private func setupTableView() {
        let columns: [(String, String, CGFloat)] = [
            ("Name", "이름", 300),
            ("Size", "크기", 80),
            ("Date", "수정일", 150),
            ("Kind", "종류", 120),
        ]

        for (id, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            tableView.addTableColumn(column)
        }

        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(doubleClickRow)
        tableView.target = self
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.style = .fullWidth
        tableView.rowHeight = 28
        tableView.menu = NSMenu()
        tableView.menu?.delegate = self
        tableView.fileURLsProvider = { [weak self] in
            self?.selectedFileURLs ?? []
        }

        // 드래그 앤 드롭
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupStatusBar() {
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBar)

        NSLayoutConstraint.activate([
            statusBar.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            statusBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    func updateFiles(_ items: [FileNode], iconCache: IconCache) {
        let selectedURLs = Set(tableView.selectedRowIndexes.compactMap { row in
            row < files.count ? files[row].url : nil
        })

        self.allFiles = items
        self.iconCache = iconCache

        // 검색 필터 유지
        let query = searchField.stringValue.lowercased()
        self.files = query.isEmpty ? items : items.filter { $0.name.lowercased().contains(query) }
        tableView.reloadData()
        statusBar.update(itemCount: items.count, totalSize: items.reduce(0) { $0 + $1.size })

        if !selectedURLs.isEmpty {
            let newSelection = IndexSet(items.enumerated().compactMap { index, node in
                selectedURLs.contains(node.url) ? index : nil
            })
            if !newSelection.isEmpty {
                tableView.selectRowIndexes(newSelection, byExtendingSelection: false)
            }
        }
    }

    func updateAddressBar(_ url: URL) {
        currentURL = url
        addressBar.setPath(url)
        updateFavoriteButton()
    }

    func flashFiles(urls: [URL]) {
        let rows = IndexSet(files.enumerated().compactMap { index, node in
            urls.contains(node.url) ? index : nil
        })
        guard !rows.isEmpty else { return }

        // 선택
        tableView.selectRowIndexes(rows, byExtendingSelection: false)
        if let first = rows.first { tableView.scrollRowToVisible(first) }

        // 깜빡임 (밝게 → 원래)
        for row in rows {
            if let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) {
                rowView.wantsLayer = true
                rowView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.6
                    context.allowsImplicitAnimation = true
                    rowView.layer?.backgroundColor = NSColor.clear.cgColor
                })
            }
        }
    }

    func animateRemovalOfSelected(completion: @escaping () -> Void) {
        let selectedRows = tableView.selectedRowIndexes
        guard !selectedRows.isEmpty else {
            completion()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.allowsImplicitAnimation = true
            for row in selectedRows {
                if let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) {
                    rowView.animator().alphaValue = 0
                }
            }
        }, completionHandler: completion)
    }

    func focusAddressBar() {
        addressBar.focus()
    }

    var selectedFileURLs: [URL] {
        tableView.selectedRowIndexes.compactMap { row in
            guard row < files.count else { return nil }
            return files[row].url
        }
    }

    private var renamingURL: URL?

    func startRenaming() {
        guard let row = tableView.selectedRowIndexes.first,
              row < files.count else { return }
        let node = files[row]

        guard node.isWritable else {
            NSSound.beep()
            if let window = view.window {
                let alert = NSAlert()
                alert.messageText = "수정할 수 없는 항목"
                alert.informativeText = "'\(node.name)'은(는) 수정 권한이 없습니다."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "확인")
                alert.beginSheetModal(for: window)
            }
            return
        }

        renamingURL = node.url
        onRenameBegan?()

        let nameColIndex = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier("Name"))
        guard nameColIndex >= 0,
              let cellView = tableView.view(atColumn: nameColIndex, row: row, makeIfNecessary: false) as? NSTableCellView,
              let textField = cellView.textField else { return }

        // 편집 모드 활성화 (Finder 스타일 둥근 모서리 + 파란 테두리)
        textField.isEditable = true
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = true
        textField.backgroundColor = .controlBackgroundColor
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 14)
        textField.wantsLayer = true
        textField.layer?.cornerRadius = 6
        textField.layer?.borderWidth = 2
        textField.layer?.borderColor = NSColor.controlAccentColor.cgColor

        // 행 높이 확장
        let editingRowHeight: CGFloat = 34
        tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))

        // 공식 NSTableView 편집 API 사용 (전체 선택으로 시작)
        tableView.editColumn(nameColIndex, row: row, with: nil, select: true)

        // 파일만 확장자 제외 선택, 폴더는 전체 선택
        let ext = node.isDirectory ? "" : node.url.pathExtension
        DispatchQueue.main.async {
            guard let editor = textField.currentEditor() else { return }
            if !ext.isEmpty {
                let name = textField.stringValue
                let extWithDot = "." + ext
                if name.hasSuffix(extWithDot) {
                    let length = name.count - extWithDot.count
                    editor.selectedRange = NSRange(location: 0, length: length)
                }
            }
        }
    }

    private func finishRenaming(textField: NSTextField) {
        textField.isEditable = false
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.layer?.cornerRadius = 0
        textField.layer?.borderWidth = 0

        // 행 높이 복원
        if let row = files.firstIndex(where: { $0.url == renamingURL }) {
            DispatchQueue.main.async { [weak self] in
                self?.tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
            }
        }

        guard let url = renamingURL,
              let node = files.first(where: { $0.url == url }) else {
            renamingURL = nil
            onRenameEnded?()
            return
        }

        let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
        renamingURL = nil
        onRenameEnded?()

        guard !newName.isEmpty, newName != node.name else {
            textField.stringValue = node.name
            return
        }

        do {
            let renamedURL = try FileOperations().rename(at: node.url, to: newName)
            onRenameComplete?(node.url, renamedURL)
        } catch {
            textField.stringValue = node.name
            if let window = view.window {
                let alert = NSAlert(error: error)
                alert.beginSheetModal(for: window)
            }
        }
    }

    @objc private func doubleClickRow() {
        let row = tableView.clickedRow
        guard row >= 0, row < files.count else { return }
        let node = files[row]
        if node.isDirectory {
            onNavigate?(node.url)
        } else {
            FileOperations().openFile(node.url)
        }
    }
}

// MARK: - NSTableViewDataSource
extension FileListContainerViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        files.count
    }

    // MARK: - Drag & Drop

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard row < files.count else { return nil }
        return files[row].url as NSURL
    }

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if dropOperation == .on { return [] }
        guard info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else { return [] }
        if info.draggingSourceOperationMask.contains(.move) {
            return .move
        }
        return .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty,
              let destination = currentURL else { return false }

        let isMove = info.draggingSourceOperationMask.contains(.move)
        do {
            if isMove {
                try FileOperations().moveFiles(urls, to: destination)
            } else {
                try FileOperations().copyFiles(urls, to: destination)
            }
            return true
        } catch {
            return false
        }
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let sort = tableView.sortDescriptors.first, let key = sort.key else { return }
        files.sort { a, b in
            let result: ComparisonResult
            switch key {
            case "Name": result = a.name.localizedStandardCompare(b.name)
            case "Size": result = a.size < b.size ? .orderedAscending : (a.size > b.size ? .orderedDescending : .orderedSame)
            case "Date": result = a.dateModified < b.dateModified ? .orderedAscending : (a.dateModified > b.dateModified ? .orderedDescending : .orderedSame)
            case "Kind": result = a.kind.localizedStandardCompare(b.kind)
            default: result = .orderedSame
            }
            return sort.ascending ? result == .orderedAscending : result == .orderedDescending
        }
        tableView.reloadData()
    }
}

// MARK: - NSTableViewDelegate
extension FileListContainerViewController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if let url = renamingURL, row < files.count, files[row].url == url {
            return 34
        }
        return 28
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("RoundedRow")
        if let existing = tableView.makeView(withIdentifier: id, owner: nil) as? RoundedRowView {
            return existing
        }
        let rowView = RoundedRowView()
        rowView.identifier = id
        return rowView
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < files.count, let columnID = tableColumn?.identifier.rawValue else { return nil }
        let node = files[row]

        let cellID = NSUserInterfaceItemIdentifier("Cell_\(columnID)")
        let cell: NSTableCellView

        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID

            let textField: NSTextField
            if columnID == "Name" {
                // Name 컬럼: 편집 가능한 NSTextField (평소엔 라벨처럼 보임)
                textField = NSTextField()
                textField.isBordered = false
                textField.drawsBackground = false
                textField.isEditable = false
                textField.delegate = self
            } else {
                textField = NSTextField(labelWithString: "")
            }
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            cell.addSubview(textField)
            cell.textField = textField

            if columnID == "Name" {
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(imageView)
                cell.imageView = imageView

                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            } else {
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])

                if columnID == "Size" {
                    textField.alignment = .right
                }
            }
        }

        switch columnID {
        case "Name":
            if node.isWritable {
                cell.textField?.stringValue = node.name
            } else {
                cell.textField?.stringValue = "🔒 " + node.name
            }
            cell.imageView?.image = iconCache?.icon(for: node)
        case "Size":
            cell.textField?.stringValue = node.formattedSize
        case "Date":
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy. MM. dd. HH:mm"
            cell.textField?.stringValue = formatter.string(from: node.dateModified)
        case "Kind":
            cell.textField?.stringValue = node.kind
        default:
            break
        }

        let isCut = cutURLs.contains(node.url)
        let isHidden = node.name.hasPrefix(".")
        let isSymlink = node.isSymlink
        if isCut {
            cell.alphaValue = 0.4
        } else if isHidden || isSymlink {
            cell.alphaValue = 0.5
        } else {
            cell.alphaValue = 1.0
        }

        return cell
    }
}

// MARK: - Quick Look
extension FileListContainerViewController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 120 { // F2 — rename
            startRenaming()
        } else if event.characters == " " {
            toggleQuickLook()
        } else if event.keyCode == 36 { // Enter/Return
            openSelectedItem()
        } else if event.keyCode == 51 && (flags == [] || flags == .command) {
            // Backspace (⌘ 있든 없든) → 뒤로가기
            NotificationCenter.default.post(name: .finderyGoBack, object: nil)
        } else if event.keyCode == 117 {
            // Forward Delete (fn+Delete) → 휴지통
            NotificationCenter.default.post(name: .finderyMoveToTrash, object: nil)
        } else {
            super.keyDown(with: event)
        }
    }

    private func openSelectedItem() {
        guard let row = tableView.selectedRowIndexes.first,
              row < files.count else { return }
        let node = files[row]
        if node.isDirectory {
            onNavigate?(node.url)
        } else {
            FileOperations().openFile(node.url)
        }
    }

    private func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        tableView.selectedRowIndexes.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let selectedRows = Array(tableView.selectedRowIndexes)
        guard index < selectedRows.count else { return nil }
        let row = selectedRows[index]
        guard row < files.count else { return nil }
        return files[row].url as NSURL
    }
}

// MARK: - NSTextFieldDelegate (rename + search)
extension FileListContainerViewController: NSTextFieldDelegate {

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control is NSSearchField { return false }
        guard renamingURL != nil else { return false }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Escape: 이름 변경 취소
            if let textField = control as? NSTextField,
               let url = renamingURL,
               let node = files.first(where: { $0.url == url }) {
                textField.stringValue = node.name
                textField.isEditable = false
                textField.isBordered = false
                textField.isBezeled = false
                textField.drawsBackground = false
                textField.font = NSFont.systemFont(ofSize: 13)
                textField.layer?.cornerRadius = 0
                textField.layer?.borderWidth = 0
                if let row = files.firstIndex(where: { $0.url == renamingURL }) {
                    DispatchQueue.main.async { [weak self] in
                        self?.tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
                    }
                }
                renamingURL = nil
                onRenameEnded?()
                view.window?.makeFirstResponder(tableView)
            }
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if obj.object is NSSearchField { return }
        guard let textField = obj.object as? NSTextField,
              renamingURL != nil else { return }
        finishRenaming(textField: textField)
    }
}

// MARK: - File Copy/Cut/Paste (standard selectors from Edit menu)
extension FileListContainerViewController {

    @objc func copy(_ sender: Any?) {
        let urls = selectedFileURLs
        guard !urls.isEmpty else { return }
        NotificationCenter.default.post(name: .finderyCopy, object: urls)
    }

    @objc func cut(_ sender: Any?) {
        let urls = selectedFileURLs
        guard !urls.isEmpty else { return }
        NotificationCenter.default.post(name: .finderyCut, object: urls)
    }

    @objc func paste(_ sender: Any?) {
        NotificationCenter.default.post(name: .finderyPaste, object: nil)
    }
}

// MARK: - Services support
extension FileListContainerViewController: NSServicesMenuRequestor {

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        let validSend = sendType == nil || sendType == .fileURL || sendType == .string
        let validReturn = returnType == nil
        if validSend && validReturn && !selectedFileURLs.isEmpty {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    @objc func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let urls = selectedFileURLs
        guard !urls.isEmpty else { return false }
        pboard.clearContents()
        pboard.writeObjects(urls as [NSURL])
        pboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)

        let filePaths = urls.map(\.path).joined(separator: "\n")
        pboard.setString(filePaths, forType: .string)
        pboard.setPropertyList(urls.map(\.absoluteString), forType: .fileURL)
        return true
    }
}

// MARK: - Context Menu (NSMenuDelegate)
extension FileListContainerViewController: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let clickedRow = tableView.clickedRow
        let urls: [URL]

        if clickedRow >= 0 {
            if !tableView.selectedRowIndexes.contains(clickedRow) {
                tableView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            }
            urls = selectedFileURLs
        } else {
            urls = []
        }

        guard let provider = contextMenuProvider else { return }
        let contextMenu = provider(urls)
        for item in contextMenu.items {
            contextMenu.removeItem(item)
            menu.addItem(item)
        }
    }
}
