@preconcurrency import AppKit
import PDFKit
import SwiftUI

struct OutlineSidebar: View {
    @EnvironmentObject private var appState: AppState
    let tab: PDFTab?

    var body: some View {
        VStack(spacing: 0) {
            if let document = tab?.document {
                let items = PDFOutlineBuilder.items(for: document)
                OutlineSidebarHeader()
                TokyoNightDivider(axis: .horizontal)

                if items.isEmpty {
                    OutlinePlaceholder(text: "No contents")
                } else {
                    PDFOutlineView(
                        items: items,
                        focusGeneration: appState.outlineFocusGeneration,
                        appState: appState
                    )
                }
            } else {
                OutlineSidebarHeader()
                TokyoNightDivider(axis: .horizontal)
                OutlinePlaceholder(text: "No document")
            }
        }
        .background {
            ZStack {
                SidebarVisualEffectBackground()
                TokyoNight.backgroundDeepColor.opacity(0.46)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(TokyoNight.borderColor.opacity(0.28))
                .frame(width: 1)
        }
    }
}

struct OutlineSidebarHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Contents")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(TokyoNight.foregroundColor)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TokyoNight.backgroundDeepColor.opacity(0.34))
    }
}

struct SidebarVisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .hudWindow
        nsView.blendingMode = .behindWindow
        nsView.state = .active
        nsView.isEmphasized = false
    }
}

struct OutlinePlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(TokyoNight.mutedColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

final class PDFOutlineItem: NSObject {
    let id: String
    let title: String
    let destination: PDFDestination?
    let pageIndex: Int?
    weak var parent: PDFOutlineItem?
    var children: [PDFOutlineItem] = []

    init(
        id: String,
        title: String,
        destination: PDFDestination?,
        pageIndex: Int?,
        parent: PDFOutlineItem?
    ) {
        self.id = id
        self.title = title
        self.destination = destination
        self.pageIndex = pageIndex
        self.parent = parent
        super.init()
    }
}

enum PDFOutlineBuilder {
    static func items(for document: PDFDocument) -> [PDFOutlineItem] {
        guard let root = document.outlineRoot else { return [] }
        return children(of: root, document: document, parent: nil, path: "")
    }

    private static func children(
        of outline: PDFOutline,
        document: PDFDocument,
        parent: PDFOutlineItem?,
        path: String
    ) -> [PDFOutlineItem] {
        (0..<outline.numberOfChildren).compactMap { index in
            guard let child = outline.child(at: index) else { return nil }

            let itemPath = path.isEmpty ? "\(index)" : "\(path).\(index)"
            let destination = child.destination
            let pageIndex = destination?.page.map { document.index(for: $0) }
            let fallbackTitle = pageIndex.map { "Page \($0 + 1)" } ?? "Untitled"
            let title = child.label?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? fallbackTitle

            let item = PDFOutlineItem(
                id: itemPath,
                title: title,
                destination: destination,
                pageIndex: pageIndex,
                parent: parent
            )
            item.children = children(of: child, document: document, parent: item, path: itemPath)
            return item
        }
    }
}

struct PDFOutlineView: NSViewRepresentable {
    let items: [PDFOutlineItem]
    let focusGeneration: Int
    let appState: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, appState: appState)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView = PDFOutlineKeyView()
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
        if #available(macOS 11.0, *) {
            outlineView.style = .plain
        }

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
        guard let outlineView = scrollView.documentView as? PDFOutlineKeyView else { return }

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

final class TokyoNightOutlineRowView: NSTableRowView {
    private static let horizontalInset: CGFloat = 10
    private var mouseInside = false {
        didSet { needsDisplay = true }
    }
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
            self.hoverTrackingArea = nil
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        mouseInside = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        mouseInside = false
    }

    override func drawBackground(in dirtyRect: NSRect) {
        if mouseInside && !isSelected {
            let hoverRect = roundedBackgroundRect()
            let path = NSBezierPath(roundedRect: hoverRect, xRadius: 7, yRadius: 7)
            TokyoNight.panel.withAlphaComponent(0.38).setFill()
            path.fill()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }

        let selectionRect = roundedBackgroundRect()
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: 7, yRadius: 7)
        TokyoNight.panelElevated.withAlphaComponent(0.82).setFill()
        path.fill()

        TokyoNight.blue.withAlphaComponent(0.18).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func roundedBackgroundRect() -> NSRect {
        let visibleWidth = enclosingScrollView?.contentView.bounds.width ?? bounds.width
        let width = min(bounds.width, visibleWidth)
        return NSRect(
            x: Self.horizontalInset,
            y: 2,
            width: max(0, width - Self.horizontalInset * 2),
            height: max(0, bounds.height - 4)
        )
    }
}

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

private extension Array where Element == PDFOutlineItem {
    func flattened() -> [PDFOutlineItem] {
        flatMap { item in
            [item] + item.children.flattened()
        }
    }
}
