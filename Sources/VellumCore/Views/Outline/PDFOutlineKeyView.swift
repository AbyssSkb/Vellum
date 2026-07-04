@preconcurrency import AppKit

final class PDFOutlineKeyView: NSOutlineView {
    weak var appState: AppState?

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
        frame.size.width = max(0, bounds.width - textX - 12)
        return frame
    }

    func focus() {
        window?.makeFirstResponder(self)
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
        guard event.type == .keyDown else { return false }

        if event.keyCode == 48 || event.charactersIgnoringModifiers == "\t" {
            appState?.toggleOutlineSidebar()
            return true
        }

        if event.keyCode == 36 || event.keyCode == 76 {
            activateSelectedItem()
            return true
        }

        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return false
        }

        let isShifted = event.modifierFlags.contains(.shift)
        let key = event.charactersIgnoringModifiers?.lowercased()

        switch key {
        case "j" where !isShifted:
            moveSelection(by: 1)
        case "k" where !isShifted:
            moveSelection(by: -1)
        case "h" where !isShifted:
            collapseSelectedItem()
        case "l" where !isShifted:
            expandSelectedItem()
        default:
            return false
        }

        return true
    }

    private func moveSelection(by delta: Int) {
        guard numberOfRows > 0 else { return }

        let startingRow = selectedRow >= 0
            ? selectedRow
            : (delta > 0 ? -1 : numberOfRows)
        let nextRow = min(max(startingRow + delta, 0), numberOfRows - 1)
        selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
        scrollRowToVisible(nextRow)
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
        guard let item = selectedOutlineItem, !item.children.isEmpty else { return }
        expandItem(item)
    }

    private func activateSelectedItem() {
        guard let item = selectedOutlineItem else { return }

        if let destination = item.destination {
            appState?.jumpToOutlineDestination(destination)
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
