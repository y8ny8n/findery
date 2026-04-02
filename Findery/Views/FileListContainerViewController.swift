import AppKit
import QuickLookUI

final class FileListContainerViewController: NSViewController {

    private let addressBar = AddressBarView()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusBar = StatusBarView()

    private var files: [FileNode] = []
    private var iconCache: IconCache?
    private var sortKey: SortKey = .name
    private var sortAscending = true

    var onNavigate: ((URL) -> Void)?

    enum SortKey: String {
        case name, size, date, kind
    }

    override func loadView() {
        view = NSView()
        setupAddressBar()
        setupTableView()
        setupStatusBar()
    }

    private func setupAddressBar() {
        addressBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addressBar)

        NSLayoutConstraint.activate([
            addressBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            addressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            addressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            addressBar.heightAnchor.constraint(equalToConstant: 28),
        ])

        addressBar.onNavigate = { [weak self] url in
            self?.onNavigate?(url)
        }
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
        self.files = items
        self.iconCache = iconCache
        tableView.reloadData()
        statusBar.update(itemCount: items.count, totalSize: items.reduce(0) { $0 + $1.size })
    }

    func updateAddressBar(_ url: URL) {
        addressBar.setPath(url)
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

        return cell
    }
}

// MARK: - Quick Look
extension FileListContainerViewController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {

    override func keyDown(with event: NSEvent) {
        if event.characters == " " {
            toggleQuickLook()
        } else {
            super.keyDown(with: event)
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
