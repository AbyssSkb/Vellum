@preconcurrency import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF outline coordinator")
struct PDFOutlineCoordinatorTests {
    @Test
    func switchingDocumentsWithIdenticalOutlinesReplacesDestinations() {
        let firstDocument = PDFDocument()
        let secondDocument = PDFDocument()
        firstDocument.insert(PDFPage(), at: 0)
        secondDocument.insert(PDFPage(), at: 0)
        let firstItem = item(for: firstDocument)
        let secondItem = item(for: secondDocument)
        let tabID = UUID()
        let coordinator = PDFOutlineView.Coordinator(
            items: [firstItem], tabID: tabID, documentID: ObjectIdentifier(firstDocument),
            appState: AppState(), language: .english
        )
        let outlineView = NSOutlineView()

        #expect(coordinator.updateItemsIfNeeded(
            [secondItem], tabID: tabID, documentID: ObjectIdentifier(secondDocument), language: .english, in: outlineView
        ))
        let displayedItem = coordinator.outlineView(outlineView, child: 0, ofItem: nil) as? PDFOutlineItem
        #expect(displayedItem?.destination?.page?.document === secondDocument)
        #expect(!coordinator.updateItemsIfNeeded(
            [item(for: secondDocument)], tabID: tabID, documentID: ObjectIdentifier(secondDocument),
            language: .english, in: outlineView
        ))
    }

    @Test
    func namedOutlineActionUsesNativeNavigationAndRecordsJumpHistory() throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        document.insert(PDFPage(), at: 1)
        let root = PDFOutline()
        let child = PDFOutline()
        child.label = "Last page"
        child.action = PDFActionNamed(name: .lastPage)
        root.insertChild(child, at: 0)
        document.outlineRoot = root
        let item = try #require(PDFOutlineBuilder.items(for: document).first)
        #expect((item.action as? PDFActionNamed)?.name == .lastPage)
        #expect(item.destination == nil)

        let reader = VellumPDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        reader.displayMode = .singlePage
        reader.document = document
        reader.layoutDocumentView()
        let originalSnapshot = try #require(reader.snapshot())
        let appState = AppState()
        appState.activeReaderController = reader

        #expect(item.activate(in: appState))
        #expect(reader.currentPage === document.page(at: 1))
        #expect(reader.jumpBackStack == [originalSnapshot])
    }

    @Test
    func outlineStateBelongsToItsTabAndSurvivesSidebarRecreation() throws {
        _ = NSApplication.shared
        let appState = AppState()
        let firstDocument = PDFDocument()
        let secondDocument = PDFDocument()
        firstDocument.insert(PDFPage(), at: 0)
        secondDocument.insert(PDFPage(), at: 0)
        let firstTab = PDFTab(url: nil, document: firstDocument)
        let secondTab = PDFTab(url: nil, document: secondDocument)
        _ = appState.tabStore.openInNewTabs([firstTab, secondTab])
        let firstItems = tree(for: firstDocument)
        let secondItems = tree(for: secondDocument)
        let coordinator = PDFOutlineView.Coordinator(
            items: firstItems, tabID: firstTab.id, documentID: ObjectIdentifier(firstDocument),
            appState: appState, language: .english
        )
        let outlineView = makeOutlineView(coordinator: coordinator)
        coordinator.restoreState(in: outlineView)
        #expect(outlineView.isItemExpanded(firstItems[0]))
        outlineView.collapseItem(firstItems[0])
        #expect(!outlineView.isItemExpanded(firstItems[0]))
        outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: firstItems[1])), byExtendingSelection: false)

        coordinator.updateItemsIfNeeded(
            secondItems, tabID: secondTab.id, documentID: ObjectIdentifier(secondDocument),
            language: .english, in: outlineView
        )
        #expect((outlineView.item(atRow: outlineView.selectedRow) as? PDFOutlineItem)?.id == "0")
        #expect(outlineView.isItemExpanded(secondItems[0]))
        let childRow = outlineView.row(forItem: secondItems[0].children[0])
        #expect(childRow >= 0)
        outlineView.selectRowIndexes(IndexSet(integer: childRow), byExtendingSelection: false)

        coordinator.updateItemsIfNeeded(
            firstItems, tabID: firstTab.id, documentID: ObjectIdentifier(firstDocument),
            language: .english, in: outlineView
        )
        #expect((outlineView.item(atRow: outlineView.selectedRow) as? PDFOutlineItem)?.id == "1")
        #expect(!outlineView.isItemExpanded(firstItems[0]))
        coordinator.saveState(in: outlineView)

        let recreated = PDFOutlineView.Coordinator(
            items: firstItems, tabID: firstTab.id, documentID: ObjectIdentifier(firstDocument),
            appState: appState, language: .english
        )
        let recreatedView = makeOutlineView(coordinator: recreated)
        recreated.restoreState(in: recreatedView)
        #expect((recreatedView.item(atRow: recreatedView.selectedRow) as? PDFOutlineItem)?.id == "1")
        #expect(!recreatedView.isItemExpanded(firstItems[0]))

        recreated.updateItemsIfNeeded(
            secondItems, tabID: firstTab.id, documentID: ObjectIdentifier(secondDocument),
            language: .english, in: recreatedView
        )
        #expect((recreatedView.item(atRow: recreatedView.selectedRow) as? PDFOutlineItem)?.id == "0")
    }

    private func makeOutlineView(coordinator: PDFOutlineView.Coordinator) -> NSOutlineView {
        let outlineView = PDFOutlineKeyView(frame: NSRect(x: 0, y: 0, width: 280, height: 400))
        let column = NSTableColumn(identifier: PDFOutlineView.Coordinator.columnIdentifier)
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.dataSource = coordinator
        outlineView.delegate = coordinator
        outlineView.reloadData()
        return outlineView
    }

    private func tree(for document: PDFDocument) -> [PDFOutlineItem] {
        let parent = item(for: document)
        parent.children = [PDFOutlineItem(
            id: "0.0", title: "Child", destination: parent.destination, pageIndex: 0, parent: parent
        )]
        let second = PDFOutlineItem(id: "1", title: "Chapter 2", destination: parent.destination, pageIndex: 0, parent: nil)
        return [parent, second]
    }

    private func item(for document: PDFDocument) -> PDFOutlineItem {
        PDFOutlineItem(
            id: "0",
            title: "Chapter 1",
            destination: PDFDestination(page: document.page(at: 0)!, at: .zero),
            pageIndex: 0,
            parent: nil
        )
    }
}
