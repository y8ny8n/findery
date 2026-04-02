import AppKit

final class AddressBarView: NSView, NSTextFieldDelegate {

    private let textField = NSTextField()
    private var suggestionsPanel: SuggestionsPanel?
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

        if event == NSTextMovement.tab.rawValue {
            if let first = suggestionsPanel?.firstSuggestion {
                textField.stringValue = first
                window?.makeFirstResponder(textField)
                textField.currentEditor()?.moveToEndOfLine(nil)
                updateSuggestions()
            }
            return
        }

        if let url = FileSystemController.expandTilde(path) {
            onNavigate?(url)
        } else {
            shakeAnimation()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            if let panel = suggestionsPanel, panel.isVisible {
                panel.selectNext()
            } else {
                updateSuggestions()
            }
            return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            suggestionsPanel?.selectPrevious()
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            if let selected = suggestionsPanel?.selectedSuggestion ?? suggestionsPanel?.firstSuggestion {
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

        if suggestionsPanel == nil {
            suggestionsPanel = SuggestionsPanel()
            suggestionsPanel?.onSelect = { [weak self] path in
                guard let self else { return }
                self.textField.stringValue = path
                self.textField.currentEditor()?.moveToEndOfLine(nil)
                self.dismissSuggestions()
                self.updateSuggestions()
            }
        }

        guard let parentWindow = window else { return }
        let fieldRect = textField.convert(textField.bounds, to: nil)
        let screenRect = parentWindow.convertToScreen(fieldRect)

        suggestionsPanel?.showBelow(
            screenRect: screenRect,
            width: textField.bounds.width,
            suggestions: suggestions,
            parentWindow: parentWindow
        )
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
        suggestionsPanel?.dismiss()
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

// MARK: - Suggestions Panel (non-activating window)

private final class SuggestionsPanel: NSObject {

    private let panel: NSPanel
    private let tableView: NSTableView
    private let scrollView = NSScrollView()
    private var suggestions: [String] = []

    var onSelect: ((String) -> Void)?

    var firstSuggestion: String? { suggestions.first }
    var isVisible: Bool { panel.isVisible }

    var selectedSuggestion: String? {
        let row = tableView.selectedRow
        guard row >= 0, row < suggestions.count else { return nil }
        return suggestions[row]
    }

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        tableView = NSTableView()

        super.init()

        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.hasShadow = true
        panel.backgroundColor = .controlBackgroundColor
        panel.isOpaque = false
        panel.level = .popUpMenu

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Path"))
        column.title = ""
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .regular
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.frame = panel.contentView!.bounds
        scrollView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(scrollView)

        tableView.delegate = self
        tableView.dataSource = self
    }

    func showBelow(screenRect: NSRect, width: CGFloat, suggestions: [String], parentWindow: NSWindow) {
        self.suggestions = suggestions
        tableView.reloadData()

        let height = min(CGFloat(suggestions.count) * 24, 240)
        let panelRect = NSRect(
            x: screenRect.origin.x,
            y: screenRect.origin.y - height - 2,
            width: width,
            height: height
        )
        panel.setFrame(panelRect, display: true)

        if !panel.isVisible {
            parentWindow.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
        }
    }

    func dismiss() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
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
}

extension SuggestionsPanel: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        suggestions.count
    }
}

extension SuggestionsPanel: NSTableViewDelegate {
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
}
