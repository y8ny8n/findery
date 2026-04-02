import AppKit

protocol TreeSidebarDelegate: AnyObject {
    func treeSidebar(_ sidebar: TreeSidebarViewController, didSelectDirectory url: URL)
}

final class TreeSidebarViewController: NSViewController {

    weak var delegate: TreeSidebarDelegate?
    private var suppressSelectionCallback = false

    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()

    private var sections: [SidebarSection] = []

    override func loadView() {
        view = NSView()
        setupScrollView()
        setupOutlineView()
        buildSections()

        NotificationCenter.default.addObserver(self, selector: #selector(favoritesChanged),
                                                name: .finderyFavoritesChanged, object: nil)
    }

    @objc private func favoritesChanged() {
        buildSections()
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
        column.title = ""
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.rowHeight = 26
        outlineView.indentationPerLevel = 14
        outlineView.style = .sourceList
        outlineView.floatsGroupRows = true

        // 우클릭 메뉴
        outlineView.menu = NSMenu()
        outlineView.menu?.delegate = self
    }

    private func buildSections() {
        let mgr = FavoritesManager.shared
        let home = FileSystemController.homeDirectory

        let favoriteItems = mgr.favorites.map { url in
            SidebarItem(
                name: url.lastPathComponent,
                url: url,
                icon: FavoritesManager.icon(for: url),
                isFavorite: true
            )
        }
        let favorites = SidebarSection(title: "즐겨찾기", items: favoriteItems)

        // 위치: 홈 디렉토리 + 외장 볼륨 (Macintosh HD 제외)
        let volumes = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes"),
            includingPropertiesForKeys: [.isVolumeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var locationItems = [
            SidebarItem(name: home.lastPathComponent, url: home, icon: "person.fill", isFavorite: false)
        ]
        for vol in volumes {
            // Macintosh HD (루트 볼륨) 제외
            if vol.lastPathComponent == "Macintosh HD" { continue }
            locationItems.append(SidebarItem(name: vol.lastPathComponent, url: vol, icon: "externaldrive.fill", isFavorite: false))
        }

        let locations = SidebarSection(title: "위치", items: locationItems)

        sections = [favorites, locations]
        outlineView.reloadData()

        for section in sections {
            outlineView.expandItem(section)
        }
    }

    func reloadTree() {
        buildSections()
    }

    func selectDirectory(_ url: URL) {
        suppressSelectionCallback = true
        defer { suppressSelectionCallback = false }
        for row in 0..<outlineView.numberOfRows {
            if let item = outlineView.item(atRow: row) as? SidebarItem,
               item.url.standardizedFileURL == url.standardizedFileURL {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
                return
            }
        }
        outlineView.deselectAll(nil)
    }

    func addCurrentToFavorites(_ url: URL) {
        FavoritesManager.shared.add(url)
    }
}

// MARK: - NSOutlineViewDataSource
extension TreeSidebarViewController: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return sections.count }
        if let section = item as? SidebarSection { return section.items.count }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return sections[index] }
        if let section = item as? SidebarSection { return section.items[index] }
        return NSNull()
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is SidebarSection
    }
}

// MARK: - NSOutlineViewDelegate
extension TreeSidebarViewController: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        return item is SidebarSection
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return item is SidebarItem
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let section = item as? SidebarSection {
            let cellID = NSUserInterfaceItemIdentifier("HeaderCell")
            let cell: NSTableCellView
            if let existing = outlineView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
                cell = existing
            } else {
                cell = NSTableCellView()
                cell.identifier = cellID
                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.font = NSFont.systemFont(ofSize: 11, weight: .bold)
                textField.textColor = .secondaryLabelColor
                cell.addSubview(textField)
                cell.textField = textField
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            cell.textField?.stringValue = section.title
            return cell
        }

        if let item = item as? SidebarItem {
            let cellID = NSUserInterfaceItemIdentifier("ItemCell")
            let cell: NSTableCellView
            if let existing = outlineView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
                cell = existing
            } else {
                cell = NSTableCellView()
                cell.identifier = cellID

                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(imageView)
                cell.imageView = imageView

                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.lineBreakMode = .byTruncatingTail
                textField.font = NSFont.systemFont(ofSize: 13)
                cell.addSubview(textField)
                cell.textField = textField

                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 18),
                    imageView.heightAnchor.constraint(equalToConstant: 18),
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }

            cell.textField?.stringValue = item.name
            let img = NSImage(systemSymbolName: item.icon, accessibilityDescription: item.name)
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            cell.imageView?.image = img?.withSymbolConfiguration(config)
            cell.imageView?.contentTintColor = .controlAccentColor
            return cell
        }

        return nil
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelectionCallback,
              let selectedRow = outlineView.selectedRowIndexes.first,
              let item = outlineView.item(atRow: selectedRow) as? SidebarItem else {
            return
        }
        delegate?.treeSidebar(self, didSelectDirectory: item.url)
    }
}

// MARK: - Context Menu
extension TreeSidebarViewController: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0,
              let item = outlineView.item(atRow: clickedRow) as? SidebarItem else { return }

        if item.isFavorite {
            let removeItem = NSMenuItem(title: "즐겨찾기에서 제거", action: #selector(removeFavorite(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = item.url
            menu.addItem(removeItem)
        }
    }

    @objc private func removeFavorite(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        FavoritesManager.shared.remove(url: url)
    }
}

// MARK: - Data Models

final class SidebarSection {
    let title: String
    let items: [SidebarItem]

    init(title: String, items: [SidebarItem]) {
        self.title = title
        self.items = items
    }
}

final class SidebarItem {
    let name: String
    let url: URL
    let icon: String
    let isFavorite: Bool

    init(name: String, url: URL, icon: String, isFavorite: Bool) {
        self.name = name
        self.url = url
        self.icon = icon
        self.isFavorite = isFavorite
    }
}
