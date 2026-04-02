import AppKit

protocol TreeSidebarDelegate: AnyObject {
    func treeSidebar(_ sidebar: TreeSidebarViewController, didSelectDirectory url: URL)
}

final class TreeSidebarViewController: NSViewController {

    weak var delegate: TreeSidebarDelegate?
    private var suppressSelectionCallback = false

    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private var rootNodes: [TreeNode] = []

    override func loadView() {
        view = NSView()
        setupScrollView()
        setupOutlineView()
        loadRootNodes()
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupOutlineView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("NameColumn"))
        column.title = "Folders"
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.rowHeight = 24
        outlineView.indentationPerLevel = 16
        outlineView.style = .sourceList
    }

    private func loadRootNodes() {
        let homeURL = FileSystemController.homeDirectory
        let rootNode = TreeNode(url: homeURL)
        rootNode.loadChildren()
        rootNodes = [rootNode]
        outlineView.reloadData()
        outlineView.expandItem(rootNode)
    }

    func selectDirectory(_ url: URL) {
        suppressSelectionCallback = true
        defer { suppressSelectionCallback = false }
        for row in 0..<outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? TreeNode,
               node.url == url {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
                return
            }
        }
    }
}

// MARK: - NSOutlineViewDataSource
extension TreeSidebarViewController: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? TreeNode else {
            return rootNodes.count
        }
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? TreeNode else {
            return rootNodes[index]
        }
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? TreeNode else { return false }
        return node.isExpandable
    }
}

// MARK: - NSOutlineViewDelegate
extension TreeSidebarViewController: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? TreeNode else { return nil }

        let cellIdentifier = NSUserInterfaceItemIdentifier("FolderCell")
        let cell: NSTableCellView

        if let existing = outlineView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            cell.identifier = cellIdentifier

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            cell.imageView = imageView

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        cell.textField?.stringValue = node.name
        cell.imageView?.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder")

        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelectionCallback,
              let selectedRow = outlineView.selectedRowIndexes.first,
              let node = outlineView.item(atRow: selectedRow) as? TreeNode else {
            return
        }
        delegate?.treeSidebar(self, didSelectDirectory: node.url)
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? TreeNode else { return }
        node.loadChildren()
        outlineView.reloadItem(node, reloadChildren: true)
    }
}

// MARK: - TreeNode
final class TreeNode {
    let url: URL
    let name: String
    var children: [TreeNode] = []
    var isExpandable: Bool
    private var childrenLoaded = false

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent

        let hasSubdirectories: Bool
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            hasSubdirectories = contents.contains { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
        } else {
            hasSubdirectories = false
        }
        self.isExpandable = hasSubdirectories
    }

    func loadChildren() {
        guard !childrenLoaded else { return }
        childrenLoaded = true

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        children = contents
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
            .map { TreeNode(url: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
