@preconcurrency import AppKit
import SwiftUI

struct MarkdownOutlineView: NSViewRepresentable {
    let items: [MarkdownOutlineItem]
    let focusGeneration: Int
    let appState: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, appState: appState)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView = MarkdownOutlineKeyView()
        outlineView.appState = appState
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.target = context.coordinator
        outlineView.doubleAction = #selector(Coordinator.doubleClick(_:))
        outlineView.headerView = nil
        outlineView.backgroundColor = .clear
        outlineView.selectionHighlightStyle = .regular
        outlineView.allowsEmptySelection = false
        outlineView.allowsMultipleSelection = false
        outlineView.indentationPerLevel = 14
        outlineView.intercellSpacing = NSSize(width: 0, height: 3)
        outlineView.rowHeight = 32
        outlineView.rowSizeStyle = .medium
        outlineView.gridStyleMask = []
        outlineView.style = .plain

        let column = NSTableColumn(identifier: Coordinator.columnIdentifier)
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 10, left: 0, bottom: 12, right: 0)
        scrollView.documentView = outlineView

        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: false)
        context.coordinator.selectInitialRow(in: outlineView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let outlineView = scrollView.documentView as? MarkdownOutlineKeyView else { return }

        context.coordinator.appState = appState
        outlineView.appState = appState

        if context.coordinator.updateItemsIfNeeded(items, in: outlineView) {
            outlineView.expandItem(nil, expandChildren: false)
            context.coordinator.selectInitialRow(in: outlineView)
        }

        if context.coordinator.lastFocusGeneration != focusGeneration {
            context.coordinator.lastFocusGeneration = focusGeneration
            DispatchQueue.main.async { [weak outlineView] in
                outlineView?.focus()
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        static let columnIdentifier = NSUserInterfaceItemIdentifier("MarkdownOutlineColumn")
        private static let cellIdentifier = NSUserInterfaceItemIdentifier("MarkdownOutlineCell")

        var appState: AppState
        var lastFocusGeneration = 0
        private var items: [MarkdownOutlineItem]
        private var itemSignature: String

        init(items: [MarkdownOutlineItem], appState: AppState) {
            self.items = items
            self.appState = appState
            itemSignature = Self.signature(for: items)
            super.init()
        }

        func updateItemsIfNeeded(_ nextItems: [MarkdownOutlineItem], in outlineView: NSOutlineView) -> Bool {
            let nextSignature = Self.signature(for: nextItems)
            guard nextSignature != itemSignature else { return false }

            let selectedID = selectedItem(in: outlineView)?.id
            let expandedIDs = expandedItemIDs(in: outlineView)
            items = nextItems
            itemSignature = nextSignature
            outlineView.reloadData()
            restoreExpandedItems(expandedIDs, in: outlineView)
            restoreSelection(selectedID, in: outlineView)
            return true
        }

        func selectInitialRow(in outlineView: NSOutlineView) {
            guard outlineView.numberOfRows > 0, outlineView.selectedRow < 0 else { return }
            outlineView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
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

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? MarkdownOutlineItem else { return nil }
            let cell = outlineView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? NSTableCellView ?? makeCell()
            cell.textField?.stringValue = item.title
            cell.textField?.toolTip = "\(item.title) · Line \(item.sourceLineIndex + 1)"
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            32
        }

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            TokyoNightOutlineRowView()
        }

        @objc func doubleClick(_ sender: NSOutlineView) {
            guard let item = selectedItem(in: sender) else { return }
            appState.jumpToMarkdownOutlineItem(item)
        }

        private func makeCell() -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = Self.cellIdentifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.maximumNumberOfLines = 1
            textField.font = .systemFont(ofSize: 13, weight: .medium)
            textField.textColor = TokyoNight.foreground.withAlphaComponent(0.88)
            textField.backgroundColor = .clear
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 0),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])

            return cell
        }

        private func selectedItem(in outlineView: NSOutlineView) -> MarkdownOutlineItem? {
            guard outlineView.selectedRow >= 0 else { return nil }
            return outlineView.item(atRow: outlineView.selectedRow) as? MarkdownOutlineItem
        }

        private func expandedItemIDs(in outlineView: NSOutlineView) -> Set<String> {
            var ids = Set<String>()
            for item in items.flattened() where outlineView.isItemExpanded(item) {
                ids.insert(item.id)
            }
            return ids
        }

        private func restoreExpandedItems(_ ids: Set<String>, in outlineView: NSOutlineView) {
            for item in items.flattened() where ids.contains(item.id) {
                outlineView.expandItem(item)
            }
        }

        private func restoreSelection(_ id: String?, in outlineView: NSOutlineView) {
            guard let id,
                  let item = items.flattened().first(where: { $0.id == id }) else {
                selectInitialRow(in: outlineView)
                return
            }

            let row = outlineView.row(forItem: item)
            guard row >= 0 else {
                selectInitialRow(in: outlineView)
                return
            }

            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.scrollRowToVisible(row)
        }

        private static func signature(for items: [MarkdownOutlineItem]) -> String {
            items.flattened()
                .map { "\($0.id)|\($0.title)|\($0.sourceLineIndex)" }
                .joined(separator: "\n")
        }
    }
}

final class MarkdownOutlineKeyView: PDFOutlineKeyView {
    override func activateSelectedItemForKeyboard() {
        guard let item = selectedMarkdownOutlineItem else { return }
        if !item.children.isEmpty, isItemExpanded(item) {
            collapseItem(item)
        } else if !item.children.isEmpty {
            expandItem(item)
        } else {
            appState?.jumpToMarkdownOutlineItem(item)
        }
    }

    private var selectedMarkdownOutlineItem: MarkdownOutlineItem? {
        guard selectedRow >= 0 else { return nil }
        return item(atRow: selectedRow) as? MarkdownOutlineItem
    }
}
