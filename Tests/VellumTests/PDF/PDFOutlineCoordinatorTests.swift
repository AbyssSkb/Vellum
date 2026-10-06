@preconcurrency import AppKit
import PDFKit
import SwiftUI
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF outline coordinator")
struct PDFOutlineCoordinatorTests {
    @Test
    func expandingNestedOutlineKeepsTitlesAndPageNumbersInPlace() async throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        let root = PDFOutlineItem(id: "0", title: "A long chapter name whose truncation must stay stable while expanding",
                                  destination: PDFDestination(page: document.page(at: 0)!, at: .zero),
                                  pageIndex: 0, parent: nil)
        let child = PDFOutlineItem(id: "0.0", title: root.title, destination: root.destination,
                                   pageIndex: 1233, parent: root)
        let grandchild = PDFOutlineItem(id: "0.0.0", title: root.title, destination: root.destination,
                                        pageIndex: 1233, parent: child)
        grandchild.children = [PDFOutlineItem(id: "0.0.0.0", title: "Fourth level", destination: root.destination,
                                             pageIndex: 0, parent: grandchild)]
        let childSibling = PDFOutlineItem(id: "0.0.1", title: "Last section", destination: root.destination,
                                          pageIndex: 0, parent: child)
        let rootSibling = PDFOutlineItem(id: "0.1", title: "Last chapter section", destination: root.destination,
                                         pageIndex: 0, parent: root)
        child.children = [grandchild, childSibling]
        root.children = [child, rootSibling]
        let host = NSHostingView(rootView: PDFOutlineView(
            items: [root], tabID: UUID(), documentID: ObjectIdentifier(document),
            focusGeneration: 0, appState: makeAppState(), language: .english
        ))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 256, height: 220),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let outline = try #require(descendants(host).compactMap { $0 as? PDFOutlineKeyView }.first)
        let firstCell = try #require(outline.view(atColumn: 0, row: 0, makeIfNecessary: true) as? PDFOutlineCellView)
        host.layoutSubtreeIfNeeded()
        let titleWidth = firstCell.titleView.bounds.width
        let pageRight = firstCell.pageNumberField.convert(firstCell.pageNumberField.bounds, to: outline).maxX
        let firstFrame = outline.frameOfCell(atColumn: 0, row: 0)

        outline.expandItem(child)
        outline.expandItem(grandchild)
        try await Task.sleep(for: .milliseconds(30))
        host.layoutSubtreeIfNeeded()
        #expect(outline.frameOfCell(atColumn: 0, row: 0) == firstFrame)
        #expect(firstCell.titleView.bounds.width == titleWidth)
        #expect(firstCell.pageNumberField.convert(firstCell.pageNumberField.bounds, to: outline).maxX == pageRight)
        let rowIndex = outline.row(forItem: grandchild)
        outline.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
        let nestedCell = try #require(outline.view(atColumn: 0, row: rowIndex, makeIfNecessary: true) as? PDFOutlineCellView)
        let rootRow = try #require(outline.rowView(atRow: 0, makeIfNecessary: true) as? TokyoNightOutlineRowView)
        let nestedRow = try #require(outline.rowView(atRow: rowIndex, makeIfNecessary: true) as? TokyoNightOutlineRowView)
        host.layoutSubtreeIfNeeded()
        nestedCell.layoutSubtreeIfNeeded()
        #expect(nestedCell.pageNumberField.convert(nestedCell.pageNumberField.bounds, to: outline).maxX == pageRight)
        #expect(nestedRow.roundedBackgroundRect().minX == rootRow.roundedBackgroundRect().minX + 28)
        #expect(nestedRow.roundedBackgroundRect().maxX == rootRow.roundedBackgroundRect().maxX)
        let leafIndex = outline.row(forItem: grandchild.children[0])
        let leafRow = try #require(outline.rowView(atRow: leafIndex, makeIfNecessary: true) as? TokyoNightOutlineRowView)
        #expect(leafRow.roundedBackgroundRect().minX + 4 == outline.frameOfCell(atColumn: 0, row: leafIndex).minX - 8)

        let leafGuides = leafRow.hierarchyGuideSegments()
        #expect(leafGuides.count == 4)
        #expect(leafGuides[0].start.x == outline.frameOfOutlineCell(atRow: rowIndex).midX)
        #expect(leafGuides[0].end.y == leafRow.bounds.midY)
        #expect(leafGuides[1].start.y == leafGuides[1].end.y)
        #expect(leafGuides[1].end.x == outline.frameOfCell(atColumn: 0, row: leafIndex).minX - 11)
        #expect(leafGuides[2].end.y == leafRow.bounds.maxY)
        #expect(leafGuides[3].start.x == outline.frameOfOutlineCell(atRow: 0).midX)
        let lastRow = try #require(outline.rowView(atRow: outline.row(forItem: rootSibling), makeIfNecessary: true)
                                  as? TokyoNightOutlineRowView)
        let lastGuides = lastRow.hierarchyGuideSegments()
        #expect(lastGuides.count == 2)
        #expect(lastGuides[0].end.y == lastRow.bounds.midY)
        #expect(rootRow.hierarchyGuideSegments().count == 1)
        outline.collapseItem(root, collapseChildren: true)
        #expect(rootRow.hierarchyGuideSegments().isEmpty)
    }

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
        let outlineView = PDFOutlineKeyView()

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

    enum Reload: CaseIterable {
        case recreation, tabSwitch, language
    }

    @Test(arguments: Reload.allCases)
    func hiddenExpandedDescendantsSurviveReload(reload: Reload) {
        _ = NSApplication.shared
        let appState = makeAppState()
        let firstDocument = PDFDocument()
        let secondDocument = PDFDocument()
        firstDocument.insert(PDFPage(), at: 0)
        secondDocument.insert(PDFPage(), at: 0)
        let firstTab = PDFTab(url: nil, document: firstDocument)
        let secondTab = PDFTab(url: nil, document: secondDocument)
        _ = appState.tabStore.openInNewTabs([firstTab, secondTab])
        let items = nestedTree(for: firstDocument)
        var coordinator = PDFOutlineView.Coordinator(
            items: items, tabID: firstTab.id, documentID: ObjectIdentifier(firstDocument),
            appState: appState, language: .english
        )
        var outline = makeOutlineView(coordinator: coordinator)
        coordinator.restoreState(in: outline)
        outline.keyDown(with: keyEvent("z", keyCode: 6))
        outline.keyDown(with: keyEvent("R", keyCode: 15))
        outline.collapseItem(items[0])
        #expect(outline.expandedIDs == ["0.0", "0.0.0"])
        #expect(outline.foldLevel == 3)
        #expect(!outline.isItemExpanded(items[0].children[0]))

        switch reload {
        case .recreation:
            coordinator.saveState(in: outline)
            coordinator = PDFOutlineView.Coordinator(
                items: items, tabID: firstTab.id, documentID: ObjectIdentifier(firstDocument),
                appState: appState, language: .english
            )
            outline = makeOutlineView(coordinator: coordinator)
            coordinator.restoreState(in: outline)
        case .tabSwitch:
            coordinator.updateItemsIfNeeded(
                tree(for: secondDocument), tabID: secondTab.id, documentID: ObjectIdentifier(secondDocument),
                language: .english, in: outline
            )
            coordinator.updateItemsIfNeeded(
                items, tabID: firstTab.id, documentID: ObjectIdentifier(firstDocument),
                language: .english, in: outline
            )
        case .language:
            coordinator.updateItemsIfNeeded(
                items, tabID: firstTab.id, documentID: ObjectIdentifier(firstDocument),
                language: .chinese, in: outline
            )
        }

        withExtendedLifetime(coordinator) {
            #expect(!outline.isItemExpanded(items[0]))
            #expect(outline.expandedIDs == ["0.0", "0.0.0"])
            #expect(outline.foldLevel == 3)
            outline.expandItem(items[0])
            #expect(outline.isItemExpanded(items[0].children[0]))
            #expect(outline.isItemExpanded(items[0].children[0].children[0]))
        }
    }

    @Test
    func manuallyOpenedBranchDoesNotChangeSavedFoldLevel() {
        _ = NSApplication.shared
        let appState = makeAppState()
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        let tab = PDFTab(url: nil, document: document)
        _ = appState.tabStore.openInNewTabs([tab])
        let items = nestedTree(for: document)
        let coordinator = PDFOutlineView.Coordinator(
            items: items, tabID: tab.id, documentID: ObjectIdentifier(document),
            appState: appState, language: .english
        )
        let outline = makeOutlineView(coordinator: coordinator)
        coordinator.restoreState(in: outline)
        outline.keyDown(with: keyEvent("z", keyCode: 6))
        outline.keyDown(with: keyEvent("M", keyCode: 46))
        outline.keyDown(with: keyEvent("z", keyCode: 6))
        outline.keyDown(with: keyEvent("o", keyCode: 31))
        #expect(outline.foldLevel == 0)
        #expect(outline.expandedIDs == ["0"])
        coordinator.saveState(in: outline)

        let recreated = PDFOutlineView.Coordinator(
            items: items, tabID: tab.id, documentID: ObjectIdentifier(document),
            appState: appState, language: .english
        )
        let recreatedView = makeOutlineView(coordinator: recreated)
        recreated.restoreState(in: recreatedView)
        #expect(recreatedView.foldLevel == 0)
        #expect(recreatedView.expandedIDs == ["0"])
        #expect(recreatedView.isItemExpanded(items[0]))
        #expect(!recreatedView.isItemExpanded(items[0].children[0]))
    }

    @Test
    func logicalFoldSelectionSurvivesSidebarRecreation() {
        _ = NSApplication.shared
        let appState = makeAppState()
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        let tab = PDFTab(url: nil, document: document)
        _ = appState.tabStore.openInNewTabs([tab])
        let items = nestedTree(for: document)
        let coordinator = PDFOutlineView.Coordinator(
            items: items, tabID: tab.id, documentID: ObjectIdentifier(document),
            appState: appState, language: .english
        )
        let outline = makeOutlineView(coordinator: coordinator)
        coordinator.restoreState(in: outline)
        outline.keyDown(with: keyEvent("z", keyCode: 6))
        outline.keyDown(with: keyEvent("R", keyCode: 15))
        let leaf = items[0].children[0].children[0].children[0]
        outline.selectFoldItem(leaf)
        outline.keyDown(with: keyEvent("z", keyCode: 6))
        outline.keyDown(with: keyEvent("C", keyCode: 8))
        #expect((outline.item(atRow: outline.selectedRow) as? PDFOutlineItem)?.id == "0")
        #expect(outline.selectedFoldItem?.id == leaf.id)
        coordinator.saveState(in: outline)

        let recreated = PDFOutlineView.Coordinator(
            items: items, tabID: tab.id, documentID: ObjectIdentifier(document),
            appState: appState, language: .english
        )
        let recreatedView = makeOutlineView(coordinator: recreated)
        recreated.restoreState(in: recreatedView)
        #expect((recreatedView.item(atRow: recreatedView.selectedRow) as? PDFOutlineItem)?.id == "0")
        #expect(recreatedView.selectedFoldItem?.id == leaf.id)
    }

    @Test
    func outlineToggleKeyClosesSidebarAfterItReceivesFocus() throws {
        _ = NSApplication.shared
        let appState = makeAppState()
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        let tab = PDFTab(url: nil, document: document)
        _ = appState.tabStore.openInNewTabs([tab])
        let coordinator = PDFOutlineView.Coordinator(
            items: tree(for: document), tabID: tab.id, documentID: ObjectIdentifier(document),
            appState: appState, language: .english
        )
        let outlineView = makeOutlineView(coordinator: coordinator)
        let window = NSWindow(
            contentRect: outlineView.frame, styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = outlineView
        window.orderFront(nil)
        defer { window.close() }
        appState.readerWindow = window
        #expect(window.makeFirstResponder(nil))

        let event = keyEvent("t", keyCode: 17, window: window)
        #expect(appState.handleKeyEvent(event))
        #expect(appState.isOutlineVisible)
        #expect(window.makeFirstResponder(outlineView))
        #expect(!appState.handleKeyEvent(event))
        outlineView.keyDown(with: event)
        #expect(!appState.isOutlineVisible)
    }

    @Test(arguments: [false, true])
    func movingBetweenVisibleOutlineRowsPreservesTopInset(longOutline: Bool) throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        let items = tree(for: document) + (longOutline ? (2..<30).map { index in
            PDFOutlineItem(
                id: "\(index)", title: "Chapter \(index + 1)",
                destination: PDFDestination(page: document.page(at: 0)!, at: .zero), pageIndex: 0, parent: nil
            )
        } : [])
        let coordinator = PDFOutlineView.Coordinator(
            items: items, tabID: UUID(), documentID: ObjectIdentifier(document),
            appState: makeAppState(), language: .english
        )
        let outlineView = makeOutlineView(coordinator: coordinator)
        outlineView.headerView = nil
        outlineView.intercellSpacing = NSSize(width: 0, height: 2)
        outlineView.rowHeight = 30
        outlineView.rowSizeStyle = .medium
        outlineView.style = .plain
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 256, height: 160))
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 10, left: 0, bottom: 12, right: 0)
        scrollView.documentView = outlineView
        coordinator.restoreState(in: outlineView)
        let window = NSWindow(
            contentRect: scrollView.frame, styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        window.orderFront(nil)
        defer { window.close() }
        scrollView.layoutSubtreeIfNeeded()
        #expect(window.makeFirstResponder(outlineView))
        let initialTop = scrollView.contentView.bounds.minY
        #expect(outlineView.visibleRect.contains(outlineView.rect(ofRow: 1)))

        outlineView.keyDown(with: keyEvent("j", keyCode: 38))
        #expect(outlineView.selectedRow == 1)
        outlineView.keyDown(with: keyEvent("k", keyCode: 40))
        #expect(outlineView.selectedRow == 0)
        #expect(scrollView.contentView.bounds.minY == initialTop)

        if longOutline {
            let lastRow = outlineView.numberOfRows - 1
            #expect(!outlineView.visibleRect.contains(outlineView.rect(ofRow: lastRow)))
            outlineView.selectRowIndexes(IndexSet(integer: lastRow - 1), byExtendingSelection: false)
            outlineView.keyDown(with: keyEvent("j", keyCode: 38))
            #expect(outlineView.selectedRow == lastRow)
            #expect(outlineView.visibleRect.contains(outlineView.rect(ofRow: lastRow)))
            #expect(scrollView.contentView.bounds.minY > initialTop)
        }
    }

    private func keyEvent(_ key: String, keyCode: UInt16, window: NSWindow? = nil) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window?.windowNumber ?? 0, context: nil,
            characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode
        )!
    }

    private func makeAppState() -> AppState {
        AppState(sessionDefaults: UserDefaults(suiteName: UUID().uuidString)!, keyboardController: KeyboardController(
            installsKeyMonitor: false, installsOpenURLObserver: false
        ))
    }

    private func makeOutlineView(coordinator: PDFOutlineView.Coordinator) -> PDFOutlineKeyView {
        let outlineView = PDFOutlineKeyView(frame: NSRect(x: 0, y: 0, width: 280, height: 400))
        outlineView.appState = coordinator.appState
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

    private func nestedTree(for document: PDFDocument) -> [PDFOutlineItem] {
        let items = tree(for: document)
        let child = items[0].children[0]
        let grandchild = PDFOutlineItem(
            id: "0.0.0", title: "Grandchild", destination: child.destination, pageIndex: 0, parent: child
        )
        grandchild.children = [PDFOutlineItem(
            id: "0.0.0.0", title: "Leaf", destination: child.destination, pageIndex: 0, parent: grandchild
        )]
        child.children = [grandchild]
        return items
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
