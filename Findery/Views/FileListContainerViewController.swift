import AppKit
import QuickLookUI

final class FileListContainerViewController: NSViewController {

    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let upButton = NSButton()
    private let addressBar = AddressBarView()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusBar = StatusBarView()

    private var files: [FileNode] = []
    private var iconCache: IconCache?
    private var sortKey: SortKey = .name
    private var sortAscending = true

    var onNavigate: ((URL) -> Void)?
    var contextMenuProvider: (([URL]) -> NSMenu)?
    var onRenameComplete: ((URL, URL) -> Void)?
    var onGoBack: (() -> Void)?
    var onGoForward: (() -> Void)?
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
            addressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            addressBar.heightAnchor.constraint(equalToConstant: 28),
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
        tableView.menu = NSMenu()
        tableView.menu?.delegate = self

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: addressBar.bottomAnchor, constant: 8),
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

        self.files = items
        self.iconCache = iconCache
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
        addressBar.setPath(url)
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

    private var renamingRow: Int?

    func startRenaming() {
        guard let row = tableView.selectedRowIndexes.first,
              row < files.count else { return }
        renamingRow = row

        guard let cellView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
              let textField = cellView.textField else { return }

        textField.isEditable = true
        textField.isSelectable = true
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true
        textField.delegate = self
        textField.window?.makeFirstResponder(textField)

        // Select filename without extension
        let name = textField.stringValue
        if let dotRange = name.range(of: ".", options: .backwards),
           dotRange.lowerBound != name.startIndex {
            let editor = textField.currentEditor()
            let nsName = name as NSString
            let selectLength = nsName.range(of: ".", options: .backwards).location
            editor?.selectedRange = NSRange(location: 0, length: selectLength)
        } else {
            textField.selectText(nil)
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
}

// MARK: - NSTableViewDelegate
extension FileListContainerViewController: NSTableViewDelegate {
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

            let textField = NSTextField(labelWithString: "")
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
            cell.textField?.stringValue = node.name
            cell.imageView?.image = iconCache?.icon(for: node)
        case "Size":
            cell.textField?.stringValue = node.formattedSize
        case "Date":
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            cell.textField?.stringValue = formatter.string(from: node.dateModified)
        case "Kind":
            cell.textField?.stringValue = node.kind
        default:
            break
        }

        let isCut = cutURLs.contains(node.url)
        cell.alphaValue = isCut ? 0.4 : 1.0

        return cell
    }
}

// MARK: - Quick Look
extension FileListContainerViewController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {

    override func keyDown(with event: NSEvent) {
        if event.characters == " " {
            toggleQuickLook()
        } else if event.keyCode == 36 { // Enter/Return
            openSelectedItem()
        } else if event.keyCode == 51 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [] {
            // Backspace (⌘ 없이) → 뒤로가기
            NotificationCenter.default.post(name: .finderyGoBack, object: nil)
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

// MARK: - Inline Rename (NSTextFieldDelegate)
extension FileListContainerViewController: NSTextFieldDelegate {

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField,
              let row = renamingRow,
              row < files.count else {
            renamingRow = nil
            return
        }

        let node = files[row]
        let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)

        // Restore label style
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        renamingRow = nil

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
        if sendType == .fileURL || sendType == .string {
            if !selectedFileURLs.isEmpty {
                return self
            }
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let urls = selectedFileURLs
        guard !urls.isEmpty else { return false }
        pboard.clearContents()
        pboard.writeObjects(urls as [NSURL])
        pboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
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
