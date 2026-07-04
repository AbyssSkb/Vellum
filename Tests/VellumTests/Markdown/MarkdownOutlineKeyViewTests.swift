import AppKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Markdown outline key view")
struct MarkdownOutlineKeyViewTests {
    @Test
    func hAndLKeysCollapseAndExpandMarkdownOutlineItems() {
        let parent = MarkdownOutlineItem(id: "parent", title: "Parent", level: 1, sourceLineIndex: 0, parent: nil)
        let child = MarkdownOutlineItem(id: "child", title: "Child", level: 2, sourceLineIndex: 1, parent: parent)
        parent.children = [child]

        let outlineView = configuredOutlineView(items: [parent])
        outlineView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        outlineView.keyDown(with: keyEvent("l"))
        #expect(outlineView.isItemExpanded(parent))

        outlineView.keyDown(with: keyEvent("h"))
        #expect(!outlineView.isItemExpanded(parent))
    }

    @Test
    func hKeySelectsParentWhenMarkdownChildIsAlreadyCollapsed() {
        let parent = MarkdownOutlineItem(id: "parent", title: "Parent", level: 1, sourceLineIndex: 0, parent: nil)
        let child = MarkdownOutlineItem(id: "child", title: "Child", level: 2, sourceLineIndex: 1, parent: parent)
        parent.children = [child]

        let outlineView = configuredOutlineView(items: [parent])
        outlineView.expandItem(parent)
        outlineView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

        outlineView.keyDown(with: keyEvent("h"))

        #expect(outlineView.selectedRow == 0)
    }

    private func configuredOutlineView(items: [MarkdownOutlineItem]) -> MarkdownOutlineKeyView {
        let outlineView = RetainingMarkdownOutlineKeyView(frame: NSRect(x: 0, y: 0, width: 240, height: 320))
        let dataSource = MarkdownOutlineTestDataSource(items: items)
        outlineView.retainedDataSource = dataSource
        outlineView.dataSource = dataSource
        outlineView.delegate = dataSource
        outlineView.headerView = nil
        outlineView.allowsEmptySelection = false
        outlineView.allowsMultipleSelection = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MarkdownOutlineTestColumn"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.reloadData()
        return outlineView
    }

    private func keyEvent(_ key: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key,
            isARepeat: false,
            keyCode: 0
        )!
    }
}

private final class MarkdownOutlineTestDataSource: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let items: [MarkdownOutlineItem]

    init(items: [MarkdownOutlineItem]) {
        self.items = items
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item = item as? MarkdownOutlineItem else { return items.count }
        return item.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item = item as? MarkdownOutlineItem else { return items[index] }
        return item.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let item = item as? MarkdownOutlineItem else { return false }
        return !item.children.isEmpty
    }
}

private final class RetainingMarkdownOutlineKeyView: MarkdownOutlineKeyView {
    var retainedDataSource: MarkdownOutlineTestDataSource?
}
