@preconcurrency import AppKit
import PDFKit

extension PDFOutlineView {
    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        static let columnIdentifier = NSUserInterfaceItemIdentifier("PDFOutlineColumn")
        private static let cellIdentifier = NSUserInterfaceItemIdentifier("PDFOutlineCell")

        var appState: AppState
        var lastFocusGeneration = 0
        private var items: [PDFOutlineItem]
        private var itemSignature: String
        private var tabID: PDFTab.ID
        private var documentID: ObjectIdentifier
        private var language: AppUILanguage

        init(
            items: [PDFOutlineItem],
            tabID: PDFTab.ID,
            documentID: ObjectIdentifier,
            appState: AppState,
            language: AppUILanguage
        ) {
            self.items = items
            self.tabID = tabID
            self.documentID = documentID
            self.appState = appState
            self.language = language
            itemSignature = Self.signature(for: items)
            super.init()
        }

        @discardableResult
        func updateItemsIfNeeded(
            _ nextItems: [PDFOutlineItem],
            tabID nextTabID: PDFTab.ID,
            documentID nextDocumentID: ObjectIdentifier,
            language nextLanguage: AppUILanguage,
            in outlineView: NSOutlineView
        ) -> Bool {
            let nextSignature = Self.signature(for: nextItems)
            guard nextSignature != itemSignature || nextTabID != tabID || nextDocumentID != documentID || nextLanguage != language else {
                return false
            }

            saveState(in: outlineView)
            items = nextItems
            itemSignature = nextSignature
            tabID = nextTabID
            documentID = nextDocumentID
            language = nextLanguage
            outlineView.deselectAll(nil)
            outlineView.reloadData()
            restoreState(in: outlineView)
            return true
        }

        func saveState(in outlineView: NSOutlineView) {
            let openTabIDs = Set(appState.tabs.map(\.id))
            appState.outlineStates = appState.outlineStates.filter { openTabIDs.contains($0.key) }
            guard openTabIDs.contains(tabID) else { return }
            appState.outlineStates[tabID] = State(
                documentID: documentID,
                selectedID: selectedItem(in: outlineView)?.id,
                expandedIDs: expandedItemIDs(in: outlineView)
            )
        }

        func restoreState(in outlineView: NSOutlineView) {
            outlineView.collapseItem(nil, collapseChildren: true)
            if let state = appState.outlineStates[tabID], state.documentID == documentID {
                restoreExpandedItems(state.expandedIDs, in: outlineView)
                restoreSelection(state.selectedID, in: outlineView)
            } else {
                for item in items where !item.children.isEmpty {
                    outlineView.expandItem(item)
                }
                selectInitialRow(in: outlineView)
            }
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
                cell.textField?.toolTip = "\(item.title) · \(language.text(.outlinePage(pageIndex + 1)))"
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
            selectedItem(in: sender)?.activate(in: appState)
        }

        private func makeCell() -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = Self.cellIdentifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.maximumNumberOfLines = 1
            textField.font = .systemFont(ofSize: 13, weight: .regular)
            textField.textColor = TokyoNight.muted
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
                .map { item in
                    let documentID = (item.destination?.page?.document).map(ObjectIdentifier.init)
                    let action = (item.action as? PDFActionNamed).map { "Named:\($0.name.rawValue)" } ?? ""
                    return "\(String(describing: documentID))|\(item.id)|\(item.title)|\(item.pageIndex ?? -1)|\(action)"
                }
                .joined(separator: "\n")
        }
    }
}
