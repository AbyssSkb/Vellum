@preconcurrency import AppKit

final class PDFOutlineKeyView: NSOutlineView {
    weak var appState: AppState?
    private var keyState = VimKeyState()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for name in [NSApplication.willResignActiveNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(clearPendingOutlineInput), name: name, object: nil)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func clearPendingOutlineInput(_ notification: Notification) {
        if let changedWindow = notification.object as? NSWindow, changedWindow !== window { return }
        keyState.clearPendingInput()
    }

    override var acceptsFirstResponder: Bool { true }

    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        var frame = super.frameOfOutlineCell(atRow: row)
        let level = outlineLevel(forRow: row)
        frame.origin.x = 20 + CGFloat(level) * indentationPerLevel
        return frame
    }

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var frame = super.frameOfCell(atColumn: column, row: row)
        let level = outlineLevel(forRow: row)
        let textX = 36 + CGFloat(level) * indentationPerLevel
        frame.origin.x = textX
        let visibleWidth = enclosingScrollView?.contentView.bounds.width ?? bounds.width
        frame.size.width = max(0, visibleWidth - textX - 12)
        return frame
    }

    func focus() {
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { keyState.clearPendingInput() }
        return resigned
    }

    override func reloadData() {
        keyState.clearPendingInput()
        super.reloadData()
    }

    override func scrollRowToVisible(_ row: Int) {
        // AppKit can normalize the top inset even when the row is already visible.
        guard !visibleRect.contains(rect(ofRow: row)) else { return }
        super.scrollRowToVisible(row)
    }

    override func keyDown(with event: NSEvent) {
        if handleOutlineKey(event) {
            return
        }

        if appState?.handleKeyEvent(event) == true {
            return
        }

        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if appState?.handleKeyEvent(event) == true {
            return
        }

        super.keyUp(with: event)
    }

    private func handleOutlineKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            keyState.clearPendingInput()
            return false
        }

        let isShifted = event.modifierFlags.contains(.shift)
        let characters = event.charactersIgnoringModifiers ?? ""
        let key = characters.lowercased()
        let isDigit = !isShifted && key.count == 1 && "0123456789".contains(key)
        let hidesSidebar = event.keyCode == 48 || event.keyCode == 53
            || key == "\t" || key == "\u{1b}" || (key == "t" && !isShifted)
        let activatesItem = event.keyCode == 36 || event.keyCode == 76

        if event.isARepeat && (isDigit || key == "g" || key == "z" || hidesSidebar || activatesItem) {
            return true
        }

        if hidesSidebar {
            keyState.clearPendingInput()
            if appState?.isOutlineVisible == true {
                appState?.toggleOutlineSidebar()
            } else {
                appState?.focusReaderSoon()
            }
            return true
        }

        if activatesItem {
            keyState.clearPendingInput()
            activateSelectedItem()
            focus()
            return true
        }

        if isDigit && keyState.handleNumericPrefixKey(key) {
            keyState.numericPrefix = String(min(Int(keyState.numericPrefix) ?? Int.max, max(1, numberOfRows)))
            return true
        }

        if key == "g" && !isShifted {
            if keyState.pendingKey == "g" {
                selectRow((keyState.consumeNumericPrefix() ?? 1) - 1)
                keyState.clearPendingInput()
            } else {
                keyState.pendingKey = "g"
            }
            return true
        }

        if keyState.pendingKey == "z", isShifted || characters != key, ["o", "c", "r", "m"].contains(key) {
            keyState.clearPendingInput()
            let branch = selectedOutlineItem.flatMap { $0.children.isEmpty ? $0.parent : $0 }
            switch key {
            case "o": if let branch { expandItem(branch, expandChildren: true) }
            case "c": if let branch { collapseItem(branch, collapseChildren: true) }
            case "r": expandItem(nil, expandChildren: true)
            default: collapseItem(nil, collapseChildren: true)
            }
            return true
        }

        if key == "z" && !isShifted {
            keyState.clearPendingInput()
            keyState.pendingKey = "z"
            return true
        }

        let count = keyState.consumeNumericPrefix()
        keyState.clearPendingInput()

        switch event.keyCode {
        case 125: moveSelection(by: 1, count: count ?? 1)
        case 126: moveSelection(by: -1, count: count ?? 1)
        case 123: collapseSelectedItem()
        case 124: expandSelectedItem()
        case 115: selectRow(0)
        case 119: selectRow(numberOfRows - 1)
        case 116: moveSelectionByViewport(direction: -1, count: count ?? 1)
        case 121: moveSelectionByViewport(direction: 1, count: count ?? 1)
        default: break
        }
        if [123, 124, 125, 126, 115, 119, 116, 121].contains(event.keyCode) { return true }

        switch key {
        case "j" where !isShifted:
            moveSelection(by: 1, count: count ?? 1)
        case "k" where !isShifted:
            moveSelection(by: -1, count: count ?? 1)
        case "h" where !isShifted:
            collapseSelectedItem()
        case "l" where !isShifted:
            expandSelectedItem()
        case "g" where isShifted:
            selectRow((count ?? numberOfRows) - 1)
        case "d", "u":
            moveSelectionByViewport(direction: key == "d" ? 1 : -1, count: count ?? 1,
                                    fraction: isShifted ? 1 : 0.5)
        case "f", "b":
            guard !isShifted else { return false }
            moveSelectionByViewport(direction: key == "f" ? 1 : -1, count: count ?? 1)
        case " ":
            moveSelectionByViewport(direction: 1, count: count ?? 1)
        default:
            return false
        }

        return true
    }

    private func moveSelectionByViewport(direction: Int, count: Int = 1, fraction: CGFloat = 1) {
        guard numberOfRows > 0 else { return }
        let startingRow = max(0, selectedRow)
        let targetY = rect(ofRow: startingRow).midY + CGFloat(direction * count) * visibleRect.height * fraction
        let targetRow = row(at: NSPoint(x: 0, y: targetY))
        selectRow(targetRow >= 0 ? targetRow : direction > 0 ? numberOfRows - 1 : 0)
    }

    private func moveSelection(by direction: Int, count: Int = 1) {
        guard numberOfRows > 0 else { return }

        let startingRow = selectedRow >= 0
            ? selectedRow
            : (direction > 0 ? -1 : numberOfRows)
        let distance = min(count, numberOfRows)
        let nextRow = direction > 0
            ? startingRow + min(distance, numberOfRows - 1 - startingRow)
            : startingRow - min(distance, startingRow)
        selectRow(nextRow)
    }

    private func selectRow(_ row: Int) {
        guard numberOfRows > 0 else { return }
        let clampedRow = min(max(row, 0), numberOfRows - 1)
        selectRowIndexes(IndexSet(integer: clampedRow), byExtendingSelection: false)
        scrollRowToVisible(clampedRow)
    }

    private func collapseSelectedItem() {
        guard let item = selectedOutlineItem else { return }

        if isItemExpanded(item) {
            collapseItem(item)
            return
        }

        guard let parent = item.parent else { return }
        let parentRow = row(forItem: parent)
        guard parentRow >= 0 else { return }
        selectRowIndexes(IndexSet(integer: parentRow), byExtendingSelection: false)
        scrollRowToVisible(parentRow)
    }

    private func expandSelectedItem() {
        guard let item = selectedOutlineItem, let child = item.children.first else { return }
        if isItemExpanded(item) {
            selectRow(row(forItem: child))
        } else {
            expandItem(item)
        }
    }

    private func activateSelectedItem() {
        guard let item = selectedOutlineItem else { return }

        if let appState, item.activate(in: appState) {
            return
        } else if !item.children.isEmpty {
            isItemExpanded(item) ? collapseItem(item) : expandItem(item)
        }
    }

    private var selectedOutlineItem: PDFOutlineItem? {
        guard selectedRow >= 0 else { return nil }
        return item(atRow: selectedRow) as? PDFOutlineItem
    }

    private func outlineLevel(forRow row: Int) -> Int {
        guard row >= 0, let item = item(atRow: row) else { return 0 }
        return level(forItem: item)
    }
}
