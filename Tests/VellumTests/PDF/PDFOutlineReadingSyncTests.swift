@preconcurrency import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Outline reading synchronization")
struct PDFOutlineReadingSyncTests {
    @Test(arguments: [false, true])
    func delayedFirstReadingLocationAlignsUnlessTheUserAlreadyBrowsed(browsed: Bool) throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        fixture.coordinator.restoreState(in: fixture.outline)
        #expect(fixture.window.makeFirstResponder(fixture.outline))
        if browsed { fixture.outline.selectFoldItem(fixture.items.last!) }
        fixture.appState.activeReaderController = fixture.reader
        fixture.appState.activeOutlineView = fixture.outline
        fixture.appState.updateOutlineReadingPosition(
            try #require(fixture.items[0].children[0].destination), from: fixture.reader
        )
        #expect(fixture.outline.selectedFoldItem === (browsed ? fixture.items.last! : fixture.items[0].children[0]))
    }

    @Test
    func readingMovementKeepsTheFocusedOutlineCursorAndScrollPosition() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        fixture.appState.outlineReadingDestination = fixture.items[0].destination
        fixture.coordinator.restoreState(in: fixture.outline)
        #expect(fixture.window.makeFirstResponder(fixture.outline))
        fixture.outline.selectFoldItem(fixture.items.last!)
        let cursor = fixture.outline.selectedFoldItem
        let scroll = fixture.scroll.contentView.bounds.origin
        let folds = fixture.outline.expandedIDs

        fixture.appState.outlineReadingDestination = fixture.items[0].children[0].destination
        fixture.coordinator.syncReadingPosition(in: fixture.outline)

        #expect(fixture.coordinator.readingItem === fixture.items[0].children[0])
        #expect(fixture.outline.selectedFoldItem === cursor)
        #expect(fixture.scroll.contentView.bounds.origin == scroll)
        #expect(fixture.outline.expandedIDs == folds)
        let focused = fixture.window.firstResponder === fixture.outline
        #expect(focused)
    }

    @Test
    func readerFocusedSynchronizationOnlyFollowsActualSectionChangesAndPreservesFolds() {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        fixture.appState.outlineReadingDestination = fixture.items[0].destination
        fixture.coordinator.restoreState(in: fixture.outline)
        fixture.outline.selectFoldItem(fixture.items.last!)
        #expect(fixture.window.makeFirstResponder(fixture.reader))
        fixture.coordinator.syncReadingPosition(in: fixture.outline)
        #expect(fixture.outline.selectedFoldItem === fixture.items.last!)

        fixture.outline.collapseItem(fixture.items[0])
        fixture.appState.outlineReadingDestination = fixture.items[0].children[0].destination
        fixture.coordinator.syncReadingPosition(in: fixture.outline)
        #expect(fixture.outline.selectedFoldItem === fixture.items[0].children[0])
        #expect(fixture.outline.item(atRow: fixture.outline.selectedRow) as? PDFOutlineItem === fixture.items[0])
        #expect(!fixture.outline.isItemExpanded(fixture.items[0]))
        let focused = fixture.window.firstResponder === fixture.reader
        #expect(focused)
    }

    @Test
    func reopeningAlignsWithReadingLocationWhileKeepingSavedFolds() {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        fixture.coordinator.restoreState(in: fixture.outline)
        fixture.outline.collapseItem(fixture.items[0])
        fixture.outline.selectFoldItem(fixture.items.last!)
        fixture.coordinator.saveState(in: fixture.outline)
        fixture.appState.outlineReadingDestination = fixture.items[0].children[0].destination
        fixture.coordinator.restoreState(in: fixture.outline)
        #expect(fixture.outline.selectedFoldItem === fixture.items[0].children[0])
        #expect(!fixture.outline.isItemExpanded(fixture.items[0]))
    }

    @Test
    func currentReadingMarkerRemainsSeparateFromKeyboardSelection() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        fixture.appState.outlineReadingDestination = fixture.items[0].destination
        fixture.coordinator.restoreState(in: fixture.outline)
        #expect(fixture.window.makeFirstResponder(fixture.outline))
        fixture.outline.selectFoldItem(fixture.items[1])
        fixture.coordinator.refreshRowAppearance(in: fixture.outline)
        let readingRow = try #require(fixture.outline.rowView(atRow: 0, makeIfNecessary: true)
                                     as? TokyoNightOutlineRowView)
        let cursorRow = try #require(fixture.outline.rowView(atRow: fixture.outline.selectedRow, makeIfNecessary: true)
                                    as? TokyoNightOutlineRowView)
        #expect(readingRow.isReadingSection)
        #expect(!readingRow.isSelected)
        #expect(cursorRow.keyboardFocused)
        #expect(!cursorRow.isReadingSection)
        #expect(fixture.window.makeFirstResponder(fixture.reader))
        fixture.coordinator.refreshRowAppearance(in: fixture.outline)
        #expect(!cursorRow.keyboardFocused)
        #expect(readingRow.isReadingSection)
    }

    private func makeFixture() -> (
        appState: AppState, items: [PDFOutlineItem], coordinator: PDFOutlineView.Coordinator,
        outline: PDFOutlineKeyView, scroll: NSScrollView, reader: VellumPDFView, window: NSWindow
    ) {
        _ = NSApplication.shared
        let appState = AppState(sessionDefaults: UserDefaults(suiteName: UUID().uuidString)!, keyboardController: KeyboardController(
            installsKeyMonitor: false, installsOpenURLObserver: false
        ))
        let document = PDFDocument()
        for index in 0..<2 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            document.insert(page, at: index)
        }
        let root = PDFOutlineItem(id: "0", title: "Chapter", destination: PDFDestination(
            page: document.page(at: 0)!, at: NSPoint(x: 300, y: 700)
        ), pageIndex: 0, parent: nil)
        root.children = [PDFOutlineItem(id: "0.0", title: "Section", destination: PDFDestination(
            page: document.page(at: 0)!, at: NSPoint(x: 300, y: 400)
        ), pageIndex: 0, parent: root)]
        let items = [root] + (1..<20).map { index in
            PDFOutlineItem(id: "\(index)", title: "Later chapter \(index)", destination: PDFDestination(
                page: document.page(at: 1)!, at: NSPoint(x: 300, y: 750 - CGFloat(index * 20))
            ), pageIndex: 1, parent: nil)
        }
        let tab = PDFTab(url: nil, document: document)
        _ = appState.tabStore.openInNewTabs([tab])
        let coordinator = PDFOutlineView.Coordinator(items: items, tabID: tab.id, documentID: ObjectIdentifier(document),
                                                     appState: appState, language: .english)
        let outline = PDFOutlineKeyView(frame: NSRect(x: 0, y: 0, width: 280, height: 160))
        outline.appState = appState
        outline.headerView = nil
        let column = NSTableColumn(identifier: PDFOutlineView.Coordinator.columnIdentifier)
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.reloadData()
        let scroll = NSScrollView(frame: outline.frame)
        scroll.documentView = outline
        let reader = VellumPDFView(frame: NSRect(x: 280, y: 0, width: 400, height: 160))
        reader.document = document
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 160),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(scroll)
        window.contentView?.addSubview(reader)
        appState.readerWindow = window
        window.contentView?.layoutSubtreeIfNeeded()
        return (appState, items, coordinator, outline, scroll, reader, window)
    }
}
