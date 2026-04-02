import AppKit

final class AddressBarView: NSView, NSTextFieldDelegate {

    private let textField = NSTextField()
    private let popover = NSPopover()
    private let suggestionsVC = SuggestionsViewController()
    private var debounceTimer: Timer?

    var onNavigate: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textField.placeholderString = "경로 입력... (Tab으로 자동완성)"
        textField.bezelStyle = .roundedBezel
        textField.delegate = self
        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        popover.contentViewController = suggestionsVC
        popover.behavior = .semitransient
        popover.animates = false

        suggestionsVC.onSelect = { [weak self] path in
            guard let self else { return }
            self.textField.stringValue = path
            self.popover.performClose(nil)
            // 포커스를 텍스트 필드로 되돌림
            DispatchQueue.main.async {
                self.window?.makeFirstResponder(self.textField)
                self.textField.currentEditor()?.moveToEndOfLine(nil)
                self.updateSuggestions()
            }
        }
    }

    func setPath(_ url: URL) {
        let home = FileSystemController.homeDirectory.path
        let path = url.path
        if path.hasPrefix(home) {
            textField.stringValue = "~" + path.dropFirst(home.count)
        } else {
            textField.stringValue = path
        }
        dismissSuggestions()
    }

    func focus() {
        window?.makeFirstResponder(textField)
        textField.selectText(nil)
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.updateSuggestions()
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        dismissSuggestions()

        guard let event = obj.userInfo?["NSTextMovement"] as? Int else { return }

        let path = textField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }

        // Tab key: autocomplete with first suggestion
        if event == NSTextMovement.tab.rawValue {
            if let first = suggestionsVC.firstSuggestion {
                textField.stringValue = first
                window?.makeFirstResponder(textField)
                textField.currentEditor()?.moveToEndOfLine(nil)
                updateSuggestions()
            }
            return
        }

        // Enter key: navigate
        if let url = FileSystemController.expandTilde(path) {
            onNavigate?(url)
        } else {
            shakeAnimation()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            if popover.isShown {
                suggestionsVC.selectNext()
            } else {
                updateSuggestions()
            }
            return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            if popover.isShown {
                suggestionsVC.selectPrevious()
            }
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            if let selected = suggestionsVC.selectedSuggestion ?? suggestionsVC.firstSuggestion {
                textField.stringValue = selected
                textField.currentEditor()?.moveToEndOfLine(nil)
                updateSuggestions()
            }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismissSuggestions()
            return true
        }
        return false
    }

    // MARK: - Suggestions

    private func updateSuggestions() {
        let input = textField.stringValue
        guard !input.isEmpty else {
            dismissSuggestions()
            return
        }

        let expanded: String
        if input.hasPrefix("~/") || input == "~" {
            expanded = (input as NSString).expandingTildeInPath
        } else {
            expanded = input
        }

        let suggestions = computeSuggestions(for: expanded, originalInput: input)

        if suggestions.isEmpty {
            dismissSuggestions()
            return
        }

        suggestionsVC.update(suggestions: suggestions)

        let newSize = NSSize(width: textField.bounds.width, height: min(CGFloat(suggestions.count) * 24, 240))
        if !popover.isShown {
            popover.contentSize = newSize
            popover.show(relativeTo: textField.bounds, of: textField, preferredEdge: .maxY)
        } else {
            popover.contentSize = newSize
        }
        // popover가 포커스를 빼앗으므로 커서 위치 보존하며 복원
        let cursorRange = textField.currentEditor()?.selectedRange
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.window?.firstResponder !== self.textField.currentEditor() {
                self.window?.makeFirstResponder(self.textField)
            }
            if let range = cursorRange {
                self.textField.currentEditor()?.selectedRange = range
            }
        }
    }

    private func computeSuggestions(for expandedPath: String, originalInput: String) -> [String] {
        let url = URL(fileURLWithPath: expandedPath)
        let parentURL: URL
        let prefix: String

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDir), isDir.boolValue {
            parentURL = url
            prefix = ""
        } else {
            parentURL = url.deletingLastPathComponent()
            prefix = url.lastPathComponent.lowercased()
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let home = FileSystemController.homeDirectory.path

        return contents
            .filter { item in
                prefix.isEmpty || item.lastPathComponent.lowercased().hasPrefix(prefix)
            }
            .sorted { a, b in
                let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if aIsDir != bIsDir { return aIsDir }
                return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
            }
            .prefix(20)
            .map { item in
                let path = item.path
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                var display: String
                if originalInput.hasPrefix("~") && path.hasPrefix(home) {
                    display = "~" + path.dropFirst(home.count)
                } else {
                    display = path
                }
                if isDir && !display.hasSuffix("/") {
                    display += "/"
                }
                return display
            }
    }

    private func dismissSuggestions() {
        if popover.isShown {
            popover.performClose(nil)
        }
        debounceTimer?.invalidate()
    }

    private func shakeAnimation() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = 0.4
        animation.values = [-8, 8, -6, 6, -4, 4, 0]
        textField.layer?.add(animation, forKey: "shake")

        textField.textColor = .systemRed
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.textField.textColor = .labelColor
        }
    }
}

// MARK: - Suggestions Dropdown ViewController

final class SuggestionsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var suggestions: [String] = []

    var onSelect: ((String) -> Void)?

    var firstSuggestion: String? { suggestions.first }

    var selectedSuggestion: String? {
        let row = tableView.selectedRow
        guard row >= 0, row < suggestions.count else { return nil }
        return suggestions[row]
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        view.addSubview(scrollView)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Path"))
        column.title = ""
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.target = self

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func update(suggestions: [String]) {
        self.suggestions = suggestions
        tableView.reloadData()
    }

    func selectNext() {
        let next = min(tableView.selectedRow + 1, suggestions.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    func selectPrevious() {
        let prev = max(tableView.selectedRow - 1, 0)
        tableView.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
        tableView.scrollRowToVisible(prev)
    }

    @objc private func rowDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < suggestions.count else { return }
        onSelect?(suggestions[row])
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        suggestions.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < suggestions.count else { return nil }
        let path = suggestions[row]

        let cellID = NSUserInterfaceItemIdentifier("SuggestionCell")
        let cell: NSTableCellView

        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
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
            textField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            textField.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 14),
                imageView.heightAnchor.constraint(equalToConstant: 14),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        cell.textField?.stringValue = path
        let isDir = path.hasSuffix("/")
        cell.imageView?.image = NSImage(systemSymbolName: isDir ? "folder.fill" : "doc.fill",
                                         accessibilityDescription: isDir ? "Folder" : "File")

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // 선택만 하이라이트, 확정은 더블클릭이나 Tab에서
    }
}
