@preconcurrency import AppKit
import SwiftUI

struct PDFOutlineView: NSViewRepresentable {
    struct State {
        let documentID: ObjectIdentifier
        let selectedID: String?
        let expandedIDs: Set<String>
        let foldLevel: Int
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
        outlineView.autoresizesOutlineColumn = false
        outlineView.intercellSpacing = NSSize(width: 0, height: 2)
        outlineView.rowHeight = 30
        // Preserve the custom title fonts and cell geometry from the first draw.
        outlineView.rowSizeStyle = .custom
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
        appState.activeOutlineView = outlineView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let outlineView = scrollView.documentView as? PDFOutlineKeyView else { return }

        context.coordinator.appState = appState
        outlineView.appState = appState
        appState.activeOutlineView = outlineView

        context.coordinator.updateItemsIfNeeded(
            items, tabID: tabID, documentID: documentID, language: language, in: outlineView
        )
        context.coordinator.syncReadingPosition(in: outlineView)

        if context.coordinator.lastFocusGeneration != focusGeneration {
            context.coordinator.lastFocusGeneration = focusGeneration
            if appState.requestsOutlineFocus {
                outlineView.requestFocus(tabID: tabID, documentID: documentID, generation: focusGeneration)
            } else {
                outlineView.cancelPendingFocus()
            }
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let outlineView = scrollView.documentView as? PDFOutlineKeyView else { return }
        outlineView.cancelPendingFocus()
        coordinator.saveState(in: outlineView)
        if coordinator.appState.activeOutlineView === outlineView {
            coordinator.appState.activeOutlineView = nil
        }
    }
}
