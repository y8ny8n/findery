import AppKit

protocol TreeSidebarDelegate: AnyObject {
    func treeSidebar(_ sidebar: TreeSidebarViewController, didSelectDirectory url: URL)
}

final class TreeSidebarViewController: NSViewController {

    weak var delegate: TreeSidebarDelegate?
    private var suppressSelectionCallback = false

    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private let bottomBar = NSView()

    private var sections: [SidebarSection] = []

    override func loadView() {
        view = NSView()
        setupScrollView()
        setupOutlineView()
        setupBottomBar()
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
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(separator)

        let settingsButton = NSButton()
        settingsButton.bezelStyle = .accessoryBarAction
        settingsButton.isBordered = false
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "환경설정")
        settingsButton.imagePosition = .imageOnly
        settingsButton.imageScaling = .scaleProportionallyDown
        settingsButton.contentTintColor = .secondaryLabelColor
        settingsButton.target = self
        settingsButton.action = #selector(openPreferences)
        settingsButton.toolTip = "환경설정"
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(settingsButton)

        NSLayoutConstraint.activate([
            bottomBar.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 28),

            separator.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            separator.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),

            settingsButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 8),
            settingsButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor, constant: 1),
            settingsButton.widthAnchor.constraint(equalToConstant: 24),
            settingsButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    @objc private func openPreferences() {
        (NSApp.delegate as? AppDelegate)?.showPreferences(nil)
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

        outlineView.menu = NSMenu()
        outlineView.menu?.delegate = self

        // 드래그 앤 드롭 등록
        outlineView.registerForDraggedTypes([.fileURL, .init("com.findery.sidebar-item")])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
    }

    private func buildSections() {
        // 확장 상태 저장
        var expandedGroupNames: Set<String> = []
        for section in sections {
            for item in section.items {
                if item.isGroup, outlineView.isItemExpanded(item) {
                    expandedGroupNames.insert(item.name)
                }
            }
        }

        let mgr = FavoritesManager.shared
        let home = FileSystemController.homeDirectory

        // 즐겨찾기 섹션 빌드
        var favoriteItems: [SidebarItem] = []
        for (entryIndex, entry) in mgr.entries.enumerated() {
            switch entry {
            case .bookmark(let path):
                let url = URL(fileURLWithPath: path)
                favoriteItems.append(SidebarItem(
                    name: url.lastPathComponent,
                    url: url,
                    icon: FavoritesManager.icon(for: url),
                    isFavorite: true
                ))
            case .group(let name, let paths):
                let children = paths.map { path -> SidebarItem in
                    let url = URL(fileURLWithPath: path)
                    return SidebarItem(
                        name: url.lastPathComponent,
                        url: url,
                        icon: FavoritesManager.icon(for: url),
                        isFavorite: true
                    )
                }
                let groupItem = SidebarItem(
                    name: name,
                    url: nil,
                    icon: "folder.fill",
                    isFavorite: true,
                    children: children,
                    entryIndex: entryIndex
                )
                // 자식에 부모 그룹 참조 설정
                for child in children {
                    child.parentGroup = groupItem
                }
                favoriteItems.append(groupItem)
            }
        }
        let favorites = SidebarSection(title: "즐겨찾기", items: favoriteItems)

        // 위치 섹션
        let volumes = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes"),
            includingPropertiesForKeys: [.isVolumeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var locationItems = [
            SidebarItem(name: home.lastPathComponent, url: home, icon: "person.fill", isFavorite: false),
            SidebarItem(name: "Macintosh HD", url: URL(fileURLWithPath: "/"), icon: "internaldrive.fill", isFavorite: false),
        ]
        for vol in volumes {
            if vol.lastPathComponent == "Macintosh HD" { continue }
            locationItems.append(SidebarItem(name: vol.lastPathComponent, url: vol, icon: "externaldrive.fill", isFavorite: false))
        }

        let locations = SidebarSection(title: "위치", items: locationItems)

        sections = [favorites, locations]
        outlineView.reloadData()

        for section in sections {
            outlineView.expandItem(section)
        }
        // 이전에 펼쳐져있던 그룹 복원
        for item in favoriteItems where item.isGroup && expandedGroupNames.contains(item.name) {
            outlineView.expandItem(item)
        }
    }

    func reloadTree() {
        buildSections()
    }

    func selectDirectory(_ url: URL) {
        suppressSelectionCallback = true
        defer { suppressSelectionCallback = false }

        var currentSection: SidebarSection?
        if let currentRow = outlineView.selectedRowIndexes.first,
           let currentItem = outlineView.item(atRow: currentRow) as? SidebarItem {
            for section in sections {
                if section.items.contains(where: { $0 === currentItem }) {
                    currentSection = section
                    break
                }
            }
        }

        if let section = currentSection {
            for row in 0..<outlineView.numberOfRows {
                if let item = outlineView.item(atRow: row) as? SidebarItem,
                   let itemURL = item.url,
                   itemURL.standardizedFileURL == url.standardizedFileURL {
                    if section.items.contains(where: { $0 === item }) {
                        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                        outlineView.scrollRowToVisible(row)
                        return
                    }
                }
            }
        }

        for row in 0..<outlineView.numberOfRows {
            if let item = outlineView.item(atRow: row) as? SidebarItem,
               let itemURL = item.url,
               itemURL.standardizedFileURL == url.standardizedFileURL {
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

    // MARK: - 그룹 entryIndex 조회

    private func entryIndex(for item: SidebarItem) -> Int? {
        if let idx = item.entryIndex { return idx }
        guard let favSection = sections.first else { return nil }
        var entryIdx = 0
        for sectionItem in favSection.items {
            if sectionItem === item { return entryIdx }
            entryIdx += 1
        }
        return nil
    }

    private func groupEntryIndex(for groupItem: SidebarItem) -> Int? {
        guard groupItem.isGroup else { return nil }
        return entryIndex(for: groupItem)
    }
}

// MARK: - NSOutlineViewDataSource
extension TreeSidebarViewController: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return sections.count }
        if let section = item as? SidebarSection { return section.items.count }
        if let sidebarItem = item as? SidebarItem, let children = sidebarItem.children {
            return children.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return sections[index] }
        if let section = item as? SidebarSection { return section.items[index] }
        if let sidebarItem = item as? SidebarItem, let children = sidebarItem.children {
            return children[index]
        }
        return NSNull()
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if item is SidebarSection { return true }
        if let sidebarItem = item as? SidebarItem { return sidebarItem.isGroup }
        return false
    }

    // MARK: - Drag Source (사이드바 항목 드래그)

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let sidebarItem = item as? SidebarItem,
              sidebarItem.isFavorite else { return nil }

        let row = outlineView.row(forItem: item)
        let pbItem = NSPasteboardItem()
        if let url = sidebarItem.url {
            pbItem.setString(url.absoluteString, forType: .fileURL)
        }
        // 사이드바 내부 이동용 식별자 (행 번호)
        pbItem.setString("\(row)", forType: .init("com.findery.sidebar-item"))
        return pbItem
    }

    // MARK: - Drop Target

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        // 즐겨찾기 섹션
        if let section = item as? SidebarSection, section.title == "즐겨찾기" {
            return .move
        }
        // 그룹 위에 드롭
        if let sidebarItem = item as? SidebarItem, sidebarItem.isGroup {
            return .move
        }
        return []
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let pasteboard = info.draggingPasteboard

        // 사이드바 내부 이동인지 확인
        if let sidebarRowStr = pasteboard.string(forType: .init("com.findery.sidebar-item")),
           let sourceRow = Int(sidebarRowStr),
           let sourceItem = outlineView.item(atRow: sourceRow) as? SidebarItem {
            return handleInternalDrop(sourceItem: sourceItem, targetItem: item, childIndex: index)
        }

        // 외부에서 폴더 드래그 (파일 목록 → 사이드바)
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }

        let mgr = FavoritesManager.shared
        for url in urls {
            // 폴더만 즐겨찾기에 추가
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            if let groupItem = item as? SidebarItem, groupItem.isGroup,
               let groupIndex = groupEntryIndex(for: groupItem) {
                // 그룹 위에 드롭 → 그룹에 추가
                mgr.addToGroup(at: groupIndex, url: url)
            } else if let section = item as? SidebarSection, section.title == "즐겨찾기" {
                // 즐겨찾기 섹션에 드롭 → 특정 위치에 삽입
                let insertIndex = index >= 0 ? index : mgr.entries.count
                mgr.insertBookmark(path: url.path, at: insertIndex)
            }
        }
        return true
    }

    private func handleInternalDrop(sourceItem: SidebarItem, targetItem: Any?, childIndex index: Int) -> Bool {
        let mgr = FavoritesManager.shared

        // 그룹 아이템을 다른 그룹 안으로 이동은 불허
        if sourceItem.isGroup, targetItem is SidebarItem {
            return false
        }

        guard let url = sourceItem.url else {
            // 그룹 자체 순서 이동
            if sourceItem.isGroup,
               let sourceIndex = entryIndex(for: sourceItem),
               targetItem is SidebarSection {
                let destIndex = index >= 0 ? index : mgr.entries.count
                mgr.moveEntry(from: sourceIndex, to: destIndex)
                return true
            }
            return false
        }

        // 같은 그룹 내 순서 변경
        if let parentGroup = sourceItem.parentGroup,
           let targetGroup = targetItem as? SidebarItem,
           parentGroup === targetGroup,
           let groupIndex = groupEntryIndex(for: parentGroup),
           index >= 0 {
            mgr.moveWithinGroup(at: groupIndex, url: url, to: index)
            return true
        }

        // 그룹 내 항목을 다른 그룹으로 이동
        if let parentGroup = sourceItem.parentGroup,
           let parentIndex = groupEntryIndex(for: parentGroup) {
            mgr.removeFromGroup(at: parentIndex, url: url)
        }

        if let groupItem = targetItem as? SidebarItem, groupItem.isGroup,
           let groupIndex = groupEntryIndex(for: groupItem) {
            // 그룹으로 이동
            mgr.addToGroup(at: groupIndex, url: url)
        } else if targetItem is SidebarSection {
            // 즐겨찾기 최상위로 이동
            // 기존 최상위 북마크 제거 후 재삽입
            mgr.remove(url: url)
            let insertIndex = index >= 0 ? index : mgr.entries.count
            mgr.insertBookmark(path: url.path, at: insertIndex)
        }

        return true
    }

}

// MARK: - Custom Row View (선택 상태 강조)

private final class SidebarRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let inset = NSRect(x: bounds.minX + 4, y: bounds.minY + 1,
                           width: bounds.width - 8, height: bounds.height - 2)
        let path = NSBezierPath(roundedRect: inset, xRadius: 6, yRadius: 6)
        if isEmphasized {
            NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
        } else {
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        }
        path.fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

// MARK: - Hover-aware Row View (그룹용)

private final class HoverRowView: NSTableRowView {
    var isHovered = false {
        didSet { needsDisplay = true }
    }
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isHovered, !isSelected else { return }
        let inset = NSRect(x: bounds.minX + 4, y: bounds.minY + 1,
                           width: bounds.width - 8, height: bounds.height - 2)
        let path = NSBezierPath(roundedRect: inset, xRadius: 6, yRadius: 6)
        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        path.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        // 그룹은 선택 불가이므로 미사용
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

// MARK: - NSOutlineViewDelegate
extension TreeSidebarViewController: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        return item is SidebarSection
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        if let sidebarItem = item as? SidebarItem {
            if sidebarItem.isGroup {
                // 그룹: 선택 불가, 펼침/접기
                let expanding = !outlineView.isItemExpanded(sidebarItem)
                if expanding {
                    outlineView.expandItem(sidebarItem)
                    // 자식 행 fade-in
                    if let children = sidebarItem.children {
                        for (i, _) in children.enumerated() {
                            let childRow = outlineView.row(forItem: children[i])
                            guard childRow >= 0,
                                  let rowView = outlineView.rowView(atRow: childRow, makeIfNecessary: false) else { continue }
                            rowView.alphaValue = 0
                            NSAnimationContext.runAnimationGroup { context in
                                context.duration = 0.2 + Double(i) * 0.04
                                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                                rowView.animator().alphaValue = 1
                            }
                        }
                    }
                } else {
                    // 접기: 자식 행 fade-out 후 collapse
                    if let children = sidebarItem.children {
                        for child in children {
                            let childRow = outlineView.row(forItem: child)
                            guard childRow >= 0,
                                  let rowView = outlineView.rowView(atRow: childRow, makeIfNecessary: false) else { continue }
                            NSAnimationContext.runAnimationGroup { context in
                                context.duration = 0.15
                                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                                rowView.animator().alphaValue = 0
                            }
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        outlineView.collapseItem(sidebarItem)
                    }
                }
                return false
            }
            return sidebarItem.url != nil
        }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForRow row: Int) -> NSTableRowView? {
        let item = outlineView.item(atRow: row)

        // 그룹 행: hover 전용 RowView
        if let sidebarItem = item as? SidebarItem, sidebarItem.isGroup {
            let id = NSUserInterfaceItemIdentifier("HoverRow")
            if let existing = outlineView.makeView(withIdentifier: id, owner: nil) as? HoverRowView {
                return existing
            }
            let rowView = HoverRowView()
            rowView.identifier = id
            return rowView
        }

        // 일반 항목: 선택 강조 RowView
        let id = NSUserInterfaceItemIdentifier("SidebarRow")
        if let existing = outlineView.makeView(withIdentifier: id, owner: nil) as? SidebarRowView {
            return existing
        }
        let rowView = SidebarRowView()
        rowView.identifier = id
        return rowView
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
            if item.isGroup {
                // 그룹 전용 셀 (폴더 아이콘 + 이름, medium weight)
                let cellID = NSUserInterfaceItemIdentifier("GroupCell")
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
                    textField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
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
                cell.textField?.textColor = .labelColor
                let folderImg = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: item.name)
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                cell.imageView?.image = folderImg?.withSymbolConfiguration(config)
                cell.imageView?.contentTintColor = .systemOrange
                return cell
            }

            // 일반 항목 셀
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
            cell.imageView?.contentTintColor = .secondaryLabelColor
            cell.textField?.textColor = .labelColor
            return cell
        }

        return nil
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        // 선택/비선택 행 스타일 업데이트
        for row in 0..<outlineView.numberOfRows {
            guard let cellView = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
                  let item = outlineView.item(atRow: row) as? SidebarItem,
                  !item.isGroup else { continue }
            let selected = outlineView.selectedRowIndexes.contains(row)
            cellView.textField?.font = NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .regular)
            cellView.textField?.textColor = .labelColor
            cellView.imageView?.contentTintColor = selected ? .controlAccentColor : .secondaryLabelColor
        }

        guard !suppressSelectionCallback,
              let selectedRow = outlineView.selectedRowIndexes.first,
              let item = outlineView.item(atRow: selectedRow) as? SidebarItem,
              let url = item.url else {
            return
        }
        delegate?.treeSidebar(self, didSelectDirectory: url)
    }

}

// MARK: - Context Menu
extension TreeSidebarViewController: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let clickedRow = outlineView.clickedRow

        // 빈 공간 우클릭 → 새 그룹만
        guard clickedRow >= 0 else {
            menu.addItem(withTitle: "새 그룹", action: #selector(addNewGroup), keyEquivalent: "").target = self
            return
        }

        guard let item = outlineView.item(atRow: clickedRow) as? SidebarItem else {
            menu.addItem(withTitle: "새 그룹", action: #selector(addNewGroup), keyEquivalent: "").target = self
            return
        }

        if item.isGroup {
            // 그룹 우클릭
            let renameItem = NSMenuItem(title: "그룹 이름 변경", action: #selector(renameGroupAction(_:)), keyEquivalent: "")
            renameItem.target = self
            renameItem.representedObject = item
            menu.addItem(renameItem)

            let deleteItem = NSMenuItem(title: "그룹 삭제", action: #selector(deleteGroupAction(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = item
            menu.addItem(deleteItem)

            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "새 그룹", action: #selector(addNewGroup), keyEquivalent: "").target = self

        } else if item.isFavorite {
            // 즐겨찾기 항목 우클릭

            // 그룹에 추가 서브메뉴
            let groups = groupItems()
            if !groups.isEmpty {
                let moveToItem = NSMenuItem(title: "그룹으로 이동", action: nil, keyEquivalent: "")
                let moveToMenu = NSMenu()
                for group in groups {
                    let mi = NSMenuItem(title: group.name, action: #selector(moveToGroupAction(_:)), keyEquivalent: "")
                    mi.target = self
                    mi.representedObject = ["item": item, "group": group]
                    moveToMenu.addItem(mi)
                }
                moveToItem.submenu = moveToMenu
                menu.addItem(moveToItem)
            }

            // 그룹 내 항목이면 "그룹에서 꺼내기"
            if item.parentGroup != nil {
                let extractItem = NSMenuItem(title: "그룹에서 꺼내기", action: #selector(extractFromGroupAction(_:)), keyEquivalent: "")
                extractItem.target = self
                extractItem.representedObject = item
                menu.addItem(extractItem)
            }

            menu.addItem(NSMenuItem.separator())

            let removeItem = NSMenuItem(title: "즐겨찾기에서 제거", action: #selector(removeFavorite(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = item.url
            menu.addItem(removeItem)

            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "새 그룹", action: #selector(addNewGroup), keyEquivalent: "").target = self
        }
    }

    private func groupItems() -> [SidebarItem] {
        guard let favSection = sections.first else { return [] }
        return favSection.items.filter { $0.isGroup }
    }

    @objc private func addNewGroup() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "새 그룹"
        alert.informativeText = "그룹 이름을 입력하세요."
        alert.addButton(withTitle: "추가")
        alert.addButton(withTitle: "취소")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.placeholderString = "그룹 이름"
        alert.accessoryView = input

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let name = input.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            FavoritesManager.shared.addGroup(name: name)
        }
    }

    @objc private func renameGroupAction(_ sender: NSMenuItem) {
        guard let groupItem = sender.representedObject as? SidebarItem,
              let groupIndex = groupEntryIndex(for: groupItem),
              let window = view.window else { return }

        let alert = NSAlert()
        alert.messageText = "그룹 이름 변경"
        alert.informativeText = "새 이름을 입력하세요."
        alert.addButton(withTitle: "변경")
        alert.addButton(withTitle: "취소")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = groupItem.name
        alert.accessoryView = input

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let name = input.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            FavoritesManager.shared.renameGroup(at: groupIndex, to: name)
        }
    }

    @objc private func deleteGroupAction(_ sender: NSMenuItem) {
        guard let groupItem = sender.representedObject as? SidebarItem,
              let groupIndex = groupEntryIndex(for: groupItem) else { return }
        FavoritesManager.shared.removeGroup(at: groupIndex)
    }

    @objc private func moveToGroupAction(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let item = info["item"] as? SidebarItem,
              let group = info["group"] as? SidebarItem,
              let url = item.url,
              let groupIndex = groupEntryIndex(for: group) else { return }
        FavoritesManager.shared.addToGroup(at: groupIndex, url: url)
    }

    @objc private func extractFromGroupAction(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? SidebarItem,
              let url = item.url,
              let parentGroup = item.parentGroup,
              let groupIndex = groupEntryIndex(for: parentGroup) else { return }
        FavoritesManager.shared.removeFromGroup(at: groupIndex, url: url)
        FavoritesManager.shared.add(url)
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
    let url: URL?
    let icon: String
    let isFavorite: Bool
    let children: [SidebarItem]?
    var entryIndex: Int?
    weak var parentGroup: SidebarItem?

    var isGroup: Bool { children != nil }

    init(name: String, url: URL?, icon: String, isFavorite: Bool, children: [SidebarItem]? = nil, entryIndex: Int? = nil) {
        self.name = name
        self.url = url
        self.icon = icon
        self.isFavorite = isFavorite
        self.children = children
        self.entryIndex = entryIndex
    }
}
