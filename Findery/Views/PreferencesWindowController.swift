import AppKit

final class PreferencesWindowController: NSWindowController {

    private let tabView = NSTabView()
    private let prefs = PreferencesManager.shared

    // Sort tab controls
    private let sortColumnPopup = NSPopUpButton()
    private let sortDirectionPopup = NSPopUpButton()
    private let foldersFirstCheckbox = NSButton(checkboxWithTitle: "폴더를 항상 위에 표시", target: nil, action: nil)

    // File open tab controls
    private let associationTableView = NSTableView()
    private var associations: [(ext: String, appURL: URL)] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "환경설정"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        setupTabs()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupTabs() {
        tabView.translatesAutoresizingMaskIntoConstraints = false

        let sortTab = NSTabViewItem(identifier: "sort")
        sortTab.label = "정렬"
        sortTab.view = buildSortView()

        let fileOpenTab = NSTabViewItem(identifier: "fileOpen")
        fileOpenTab.label = "파일 열기"
        fileOpenTab.view = buildFileOpenView()

        tabView.addTabViewItem(sortTab)
        tabView.addTabViewItem(fileOpenTab)

        guard let contentView = window?.contentView else { return }
        contentView.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Sort Tab

    private func buildSortView() -> NSView {
        let container = NSView()

        let columnLabel = NSTextField(labelWithString: "기본 정렬 기준:")
        let directionLabel = NSTextField(labelWithString: "정렬 방향:")

        let columns = [("Name", "이름"), ("Size", "크기"), ("Date", "수정일"), ("Kind", "종류")]
        sortColumnPopup.removeAllItems()
        for (key, title) in columns {
            sortColumnPopup.addItem(withTitle: title)
            sortColumnPopup.lastItem?.representedObject = key
        }
        let currentColumn = prefs.defaultSortColumn
        if let index = columns.firstIndex(where: { $0.0 == currentColumn }) {
            sortColumnPopup.selectItem(at: index)
        }
        sortColumnPopup.target = self
        sortColumnPopup.action = #selector(sortSettingChanged)

        sortDirectionPopup.removeAllItems()
        sortDirectionPopup.addItems(withTitles: ["오름차순 ↑", "내림차순 ↓"])
        sortDirectionPopup.selectItem(at: prefs.defaultSortAscending ? 0 : 1)
        sortDirectionPopup.target = self
        sortDirectionPopup.action = #selector(sortSettingChanged)

        foldersFirstCheckbox.state = prefs.foldersFirst ? .on : .off
        foldersFirstCheckbox.target = self
        foldersFirstCheckbox.action = #selector(sortSettingChanged)

        let description = NSTextField(wrappingLabelWithString: "모든 폴더에서 파일 목록을 열 때 이 정렬 기준이 적용됩니다. 폴더 안에서 컬럼 헤더를 클릭하면 임시로 변경할 수 있습니다.")
        description.font = .systemFont(ofSize: 11)
        description.textColor = .secondaryLabelColor

        for v in [columnLabel, sortColumnPopup, directionLabel, sortDirectionPopup, foldersFirstCheckbox, description] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }

        NSLayoutConstraint.activate([
            columnLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            columnLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            columnLabel.widthAnchor.constraint(equalToConstant: 100),

            sortColumnPopup.centerYAnchor.constraint(equalTo: columnLabel.centerYAnchor),
            sortColumnPopup.leadingAnchor.constraint(equalTo: columnLabel.trailingAnchor, constant: 8),
            sortColumnPopup.widthAnchor.constraint(equalToConstant: 140),

            directionLabel.topAnchor.constraint(equalTo: columnLabel.bottomAnchor, constant: 16),
            directionLabel.leadingAnchor.constraint(equalTo: columnLabel.leadingAnchor),
            directionLabel.widthAnchor.constraint(equalToConstant: 100),

            sortDirectionPopup.centerYAnchor.constraint(equalTo: directionLabel.centerYAnchor),
            sortDirectionPopup.leadingAnchor.constraint(equalTo: directionLabel.trailingAnchor, constant: 8),
            sortDirectionPopup.widthAnchor.constraint(equalToConstant: 140),

            foldersFirstCheckbox.topAnchor.constraint(equalTo: directionLabel.bottomAnchor, constant: 20),
            foldersFirstCheckbox.leadingAnchor.constraint(equalTo: columnLabel.leadingAnchor),

            description.topAnchor.constraint(equalTo: foldersFirstCheckbox.bottomAnchor, constant: 20),
            description.leadingAnchor.constraint(equalTo: columnLabel.leadingAnchor),
            description.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])

        return container
    }

    @objc private func sortSettingChanged() {
        if let key = sortColumnPopup.selectedItem?.representedObject as? String {
            prefs.defaultSortColumn = key
        }
        prefs.defaultSortAscending = sortDirectionPopup.indexOfSelectedItem == 0
        prefs.foldersFirst = foldersFirstCheckbox.state == .on
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    // MARK: - File Open Tab

    private func buildFileOpenView() -> NSView {
        let container = NSView()

        let description = NSTextField(wrappingLabelWithString: "확장자별로 파일을 열 기본 앱을 지정합니다. 설정이 없으면 시스템 기본 앱으로 열립니다.")
        description.font = .systemFont(ofSize: 11)
        description.textColor = .secondaryLabelColor
        description.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(description)

        // Table
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let iconCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("icon"))
        iconCol.title = ""
        iconCol.width = 24
        iconCol.isEditable = false

        let extCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ext"))
        extCol.title = "확장자"
        extCol.width = 80
        extCol.isEditable = false

        let appCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        appCol.title = "앱"
        appCol.width = 200
        appCol.isEditable = false

        associationTableView.addTableColumn(iconCol)
        associationTableView.addTableColumn(extCol)
        associationTableView.addTableColumn(appCol)
        associationTableView.delegate = self
        associationTableView.dataSource = self
        associationTableView.rowHeight = 24
        associationTableView.usesAlternatingRowBackgroundColors = true
        scrollView.documentView = associationTableView
        container.addSubview(scrollView)

        // Buttons
        let addButton = NSButton(title: "+", target: self, action: #selector(addAssociation))
        addButton.bezelStyle = .smallSquare
        addButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(addButton)

        let removeButton = NSButton(title: "−", target: self, action: #selector(removeAssociation))
        removeButton.bezelStyle = .smallSquare
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(removeButton)

        NSLayoutConstraint.activate([
            description.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            description.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            description.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: description.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -4),

            addButton.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            addButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            addButton.widthAnchor.constraint(equalToConstant: 24),
            addButton.heightAnchor.constraint(equalToConstant: 24),

            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 2),
            removeButton.bottomAnchor.constraint(equalTo: addButton.bottomAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 24),
            removeButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        reloadAssociations()
        return container
    }

    private func reloadAssociations() {
        associations = prefs.allAssociations()
        associationTableView.reloadData()
    }

    @objc private func addAssociation() {
        let alert = NSAlert()
        alert.messageText = "파일 확장자 입력"
        alert.informativeText = "기본 앱을 지정할 확장자를 입력하세요 (예: md, txt, png)"
        alert.addButton(withTitle: "다음")
        alert.addButton(withTitle: "취소")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = "md"
        alert.accessoryView = textField

        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let ext = textField.stringValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ".", with: "")
                .lowercased()
            guard !ext.isEmpty else { return }
            self?.pickApp(forExtension: ext)
        }
    }

    private func pickApp(forExtension ext: String) {
        let panel = NSOpenPanel()
        panel.title = ".\(ext) 파일을 열 앱 선택"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let appURL = panel.url else { return }
            self?.prefs.setDefaultApp(appURL, forExtension: ext)
            self?.reloadAssociations()
        }
    }

    @objc private func removeAssociation() {
        let row = associationTableView.selectedRow
        guard row >= 0, row < associations.count else { return }
        prefs.removeDefaultApp(forExtension: associations[row].ext)
        reloadAssociations()
    }

    func showAndActivate() {
        reloadAssociations()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Table Data Source / Delegate

extension PreferencesWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        associations.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < associations.count else { return nil }
        let assoc = associations[row]
        let colID = tableColumn?.identifier.rawValue ?? ""

        switch colID {
        case "icon":
            let imageView = NSImageView()
            let icon = NSWorkspace.shared.icon(forFile: assoc.appURL.path)
            icon.size = NSSize(width: 16, height: 16)
            imageView.image = icon
            return imageView

        case "ext":
            let cell = NSTextField(labelWithString: ".\(assoc.ext)")
            cell.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            return cell

        case "app":
            let appName = assoc.appURL.deletingPathExtension().lastPathComponent
            return NSTextField(labelWithString: appName)

        default:
            return nil
        }
    }
}
