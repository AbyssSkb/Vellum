@preconcurrency import AppKit
import PDFKit

final class PDFOutlineCellView: NSTableCellView {
    let titleView = PDFOutlineTitleView()
    let pageNumberField = NSTextField(labelWithString: "")
}

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
        private(set) var readingItem: PDFOutlineItem?
        private var awaitsReadingAlignment = false

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
            in outlineView: PDFOutlineKeyView
        ) -> Bool {
            let nextSignature = Self.signature(for: nextItems)
            guard nextSignature != itemSignature || nextTabID != tabID || nextDocumentID != documentID || nextLanguage != language else {
                return false
            }

            let readerChanged = nextTabID != tabID || nextDocumentID != documentID
            saveState(in: outlineView)
            items = nextItems
            itemSignature = nextSignature
            tabID = nextTabID
            documentID = nextDocumentID
            language = nextLanguage
            outlineView.deselectAll(nil)
            outlineView.reloadData()
            restoreState(in: outlineView, alignReadingPosition: readerChanged)
            return true
        }

        func saveState(in outlineView: PDFOutlineKeyView) {
            let openTabIDs = Set(appState.tabs.map(\.id))
            appState.outlineStates = appState.outlineStates.filter { openTabIDs.contains($0.key) }
            guard openTabIDs.contains(tabID) else { return }
            appState.outlineStates[tabID] = State(
                documentID: documentID,
                selectedID: outlineView.selectedFoldItem?.id,
                expandedIDs: outlineView.expandedIDs,
                foldLevel: outlineView.foldLevel
            )
        }

        func restoreState(in outlineView: PDFOutlineKeyView, alignReadingPosition: Bool = true) {
            if let state = appState.outlineStates[tabID], state.documentID == documentID {
                outlineView.restoreFolding(items: items, expandedIDs: state.expandedIDs, foldLevel: state.foldLevel)
                restoreSelection(state.selectedID, in: outlineView)
            } else {
                let expandedIDs = Set(items.filter { !$0.children.isEmpty }.map(\.id))
                outlineView.restoreFolding(items: items, expandedIDs: expandedIDs, foldLevel: 1)
                selectInitialRow(in: outlineView)
            }
            syncReadingPosition(in: outlineView, alignSelection: alignReadingPosition)
        }

        func syncReadingPosition(in outlineView: PDFOutlineKeyView, alignSelection: Bool = false) {
            let nextItem: PDFOutlineItem?
            let hasReadingPosition: Bool
            if let destination = appState.outlineReadingDestination,
               destination.page?.document.map(ObjectIdentifier.init) == documentID {
                hasReadingPosition = true
                nextItem = OutlineReadingMatcher.item(
                    for: destination, in: items, preferredID: appState.outlineReadingItemID
                )
            } else {
                hasReadingPosition = false
                nextItem = nil
            }
            if alignSelection { awaitsReadingAlignment = !hasReadingPosition }
            let shouldAlign = alignSelection || awaitsReadingAlignment
            if hasReadingPosition { awaitsReadingAlignment = false }
            let sectionChanged = nextItem?.id != readingItem?.id
            readingItem = nextItem
            if let nextItem, shouldAlign || (sectionChanged && readerIsFocused(in: outlineView.window)) {
                outlineView.selectFoldItem(nextItem)
            }
            refreshRowAppearance(in: outlineView)
        }

        func cancelPendingReadingAlignment() {
            awaitsReadingAlignment = false
        }

        func refreshRowAppearance(in outlineView: PDFOutlineKeyView) {
            var visibleReadingItem = readingItem
            while let item = visibleReadingItem, outlineView.row(forItem: item) < 0 {
                visibleReadingItem = item.parent
            }
            let readingRow = visibleReadingItem.map { outlineView.row(forItem: $0) }
            let keyboardFocused = outlineView.window?.firstResponder === outlineView
            outlineView.enumerateAvailableRowViews { row, index in
                guard let row = row as? TokyoNightOutlineRowView else { return }
                row.keyboardFocused = keyboardFocused
                row.isReadingSection = index == readingRow
                row.needsDisplay = true
            }
        }

        private func readerIsFocused(in window: NSWindow?) -> Bool {
            var responderView = window?.firstResponder as? NSView
            while let view = responderView {
                if view is VellumPDFView { return true }
                responderView = view.superview
            }
            return false
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
            ) as? PDFOutlineCellView ?? makeCell()

            cell.titleView.title = item.title
            cell.pageNumberField.stringValue = item.pageIndex.map { String($0 + 1) } ?? ""
            cell.pageNumberField.isHidden = item.pageIndex == nil
            if let pageIndex = item.pageIndex {
                cell.textField?.toolTip = "\(item.title) · \(language.text(.outlinePage(pageIndex + 1)))"
            } else {
                cell.textField?.toolTip = item.title
            }
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            (item as? PDFOutlineItem)?.parent == nil ? 34 : 28
        }

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            let row = TokyoNightOutlineRowView()
            row.hierarchyLevel = outlineView.level(forItem: item)
            row.levelIndent = outlineView.indentationPerLevel
            row.contentIndent = CGFloat(row.hierarchyLevel) * row.levelIndent
            row.isBranch = (item as? PDFOutlineItem)?.children.isEmpty == false
            row.outlineItem = item as? PDFOutlineItem
            row.keyboardFocused = outlineView.window?.firstResponder === outlineView
            var visibleReadingItem = readingItem
            while let reading = visibleReadingItem, outlineView.row(forItem: reading) < 0 {
                visibleReadingItem = reading.parent
            }
            row.isReadingSection = (item as? PDFOutlineItem)?.id == visibleReadingItem?.id
            return row
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            cancelPendingReadingAlignment()
            guard let outlineView = notification.object as? PDFOutlineKeyView else { return }
            if let item = notification.userInfo?["NSObject"] as? PDFOutlineItem {
                outlineView.recordExpansion(of: item, expanded: true)
            }
            refreshRowAppearance(in: outlineView)
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            cancelPendingReadingAlignment()
            guard let outlineView = notification.object as? PDFOutlineKeyView else { return }
            if let item = notification.userInfo?["NSObject"] as? PDFOutlineItem {
                outlineView.recordExpansion(of: item, expanded: false)
            }
            refreshRowAppearance(in: outlineView)
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            cancelPendingReadingAlignment()
            guard let outlineView = notification.object as? PDFOutlineKeyView else { return }
            outlineView.recordSelection()
            refreshRowAppearance(in: outlineView)
        }

        @objc func doubleClick(_ sender: NSOutlineView) {
            if selectedItem(in: sender)?.activate(in: appState) == true {
                appState.focusReaderContent()
            }
        }

        private func makeCell() -> PDFOutlineCellView {
            let cell = PDFOutlineCellView()
            cell.identifier = Self.cellIdentifier

            let titleView = cell.titleView
            titleView.translatesAutoresizingMaskIntoConstraints = false
            let textField = titleView.textField
            textField.lineBreakMode = .byTruncatingTail
            textField.maximumNumberOfLines = 1
            textField.font = .systemFont(ofSize: 13, weight: .regular)
            textField.textColor = TokyoNight.muted
            textField.backgroundColor = .clear
            titleView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            cell.textField = textField

            let pageNumberField = cell.pageNumberField
            pageNumberField.translatesAutoresizingMaskIntoConstraints = false
            pageNumberField.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
            pageNumberField.alignment = .right
            pageNumberField.textColor = TokyoNight.muted
            pageNumberField.setContentHuggingPriority(.required, for: .horizontal)
            pageNumberField.setContentCompressionResistancePriority(.required, for: .horizontal)

            let stack = NSStackView(views: [titleView, pageNumberField])
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.orientation = .horizontal
            stack.distribution = .fill
            stack.alignment = .centerY
            stack.spacing = 8
            stack.detachesHiddenViews = true
            cell.addSubview(stack)

            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])

            return cell
        }

        private func selectedItem(in outlineView: NSOutlineView) -> PDFOutlineItem? {
            guard outlineView.selectedRow >= 0 else { return nil }
            return outlineView.item(atRow: outlineView.selectedRow) as? PDFOutlineItem
        }

        private func restoreSelection(_ id: String?, in outlineView: PDFOutlineKeyView) {
            guard let id,
                  let item = items.flattened().first(where: { $0.id == id }) else {
                selectInitialRow(in: outlineView)
                return
            }

            outlineView.selectFoldItem(item)
        }

        private static func signature(for items: [PDFOutlineItem]) -> String {
            items.flattened()
                .map { item in
                    let documentID = (item.destination?.page?.document).map(ObjectIdentifier.init)
                    let action = (item.action as? PDFActionNamed).map { "Named:\($0.name.rawValue)" } ?? ""
                    return "\(String(describing: documentID))|\(item.id)|\(item.title)|\(item.pageIndex ?? -1)|\(String(describing: item.destination?.point))|\(action)"
                }
                .joined(separator: "\n")
        }
    }
}
