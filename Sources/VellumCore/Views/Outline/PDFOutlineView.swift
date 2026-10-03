@preconcurrency import AppKit
import SwiftUI

struct PDFOutlineView: NSViewRepresentable {
    struct State {
        let documentID: ObjectIdentifier
        let selectedID: String?
        let expandedIDs: Set<String>
    }

    let items: [PDFOutlineItem]
    let tabID: PDFTab.ID
    let documentID: ObjectIdentifier
    let focusGeneration: Int
    let appState: AppState
    let language: AppUILanguage

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, tabID: tabID, documentID: documentID, appState: appState, language: language)
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
        outlineView.intercellSpacing = NSSize(width: 0, height: 2)
        outlineView.rowHeight = 30
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
        context.coordinator.restoreState(in: outlineView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let outlineView = scrollView.documentView as? PDFOutlineKeyView else { return }

        context.coordinator.appState = appState
        outlineView.appState = appState

        context.coordinator.updateItemsIfNeeded(
            items, tabID: tabID, documentID: documentID, language: language, in: outlineView
        )

        if context.coordinator.lastFocusGeneration != focusGeneration {
            context.coordinator.lastFocusGeneration = focusGeneration
            DispatchQueue.main.async { [weak outlineView] in
                outlineView?.focus()
            }
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let outlineView = scrollView.documentView as? PDFOutlineKeyView else { return }
        coordinator.saveState(in: outlineView)
    }
}
