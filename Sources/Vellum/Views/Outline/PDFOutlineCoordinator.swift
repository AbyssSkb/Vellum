@preconcurrency import AppKit

extension PDFOutlineView {
    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        static let columnIdentifier = NSUserInterfaceItemIdentifier("PDFOutlineColumn")
        private static let cellIdentifier = NSUserInterfaceItemIdentifier("PDFOutlineCell")

        var appState: AppState
        var lastFocusGeneration = 0
        private var items: [PDFOutlineItem]
        private var itemSignature: String

        init(items: [PDFOutlineItem], appState: AppState) {
            self.items = items
            self.appState = appState
            itemSignature = Self.signature(for: items)
            super.init()
        }

        func updateItemsIfNeeded(_ nextItems: [PDFOutlineItem], in outlineView: NSOutlineView) -> Bool {
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
            guard let item = item as? PDFOutlineItem else { return items.count }
            return item.children.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let item = item as? PDFOutlineItem else { return items[index] }
            return item.children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let item = item as? PDFOutlineItem else { return false }
            return !item.children.isEmpty
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            viewFor tableColumn: NSTableColumn?,
            item: Any
        ) -> NSView? {
            guard let item = item as? PDFOutlineItem else { return nil }

            let cell = outlineView.makeView(
                withIdentifier: Self.cellIdentifier,
                owner: self
            ) as? NSTableCellView ?? makeCell()

            cell.textField?.stringValue = item.title
            if let pageIndex = item.pageIndex {
                cell.textField?.toolTip = "\(item.title) · Page \(pageIndex + 1)"
            } else {
                cell.textField?.toolTip = item.title
            }
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            32
        }

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            TokyoNightOutlineRowView()
        }

        @objc func doubleClick(_ sender: NSOutlineView) {
            guard let destination = selectedItem(in: sender)?.destination else { return }
            appState.jumpToOutlineDestination(destination)
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

        private func selectedItem(in outlineView: NSOutlineView) -> PDFOutlineItem? {
            guard outlineView.selectedRow >= 0 else { return nil }
            return outlineView.item(atRow: outlineView.selectedRow) as? PDFOutlineItem
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

        private static func signature(for items: [PDFOutlineItem]) -> String {
            items.flattened()
                .map { "\($0.id)|\($0.title)|\($0.pageIndex ?? -1)" }
                .joined(separator: "\n")
        }
    }
}
