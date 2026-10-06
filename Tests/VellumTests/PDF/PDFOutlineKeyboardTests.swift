@preconcurrency import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF outline keyboard", .serialized)
struct PDFOutlineKeyboardTests {
    @Test
    func countsMoveVisibleRowsAndClampWithoutOverflow() {
        let fixture = Fixture()
        defer { fixture.window.close() }

        fixture.send("1")
        fixture.send("2")
        fixture.send("j")
        #expect(fixture.outline.selectedRow == 12)
        fixture.send("j", repeating: true)
        #expect(fixture.outline.selectedRow == 13)
        fixture.send("5")
        fixture.send("k")
        #expect(fixture.outline.selectedRow == 8)
        fixture.send("2")
        fixture.send("2", repeating: true)
        fixture.send("j")
        #expect(fixture.outline.selectedRow == 10)

        for _ in 0..<30 { fixture.send("9") }
        fixture.send("j")
        #expect(fixture.outline.selectedRow == fixture.outline.numberOfRows - 1)
        for _ in 0..<30 { fixture.send("9") }
        fixture.send("k")
        #expect(fixture.outline.selectedRow == 0)
    }

    @Test
    func firstLastAndNumberedJumpsKeepPrefixesLocal() {
        let fixture = Fixture()
        defer { fixture.window.close() }
        fixture.outline.selectRowIndexes(IndexSet(integer: 10), byExtendingSelection: false)

        fixture.send("g")
        fixture.send("g", repeating: true)
        #expect(fixture.outline.selectedRow == 10)
        fixture.send("g")
        #expect(fixture.outline.selectedRow == 0)
        fixture.send("G", modifiers: .shift)
        #expect(fixture.outline.selectedRow == fixture.outline.numberOfRows - 1)
        fixture.send("7")
        fixture.send("G", modifiers: .shift)
        #expect(fixture.outline.selectedRow == 6)
        fixture.send("9")
        fixture.send("g")
        fixture.send("g")
        #expect(fixture.outline.selectedRow == 8)

        fixture.send("g")
        fixture.send("j")
        #expect(fixture.outline.selectedRow == 9)
        fixture.send("g")
        fixture.send("g")
        #expect(fixture.outline.selectedRow == 0)
    }

    @Test
    func hierarchyKeysExpandDescendCollapseAndAscend() {
        let items = tree()
        let fixture = Fixture(items: items)
        defer { fixture.window.close() }
        let root = items[0]
        let child = root.children[0]
        let grandchild = child.children[0]
        fixture.outline.collapseItem(root, collapseChildren: true)

        fixture.send("l")
        #expect(fixture.outline.isItemExpanded(root))
        #expect(fixture.selectedItem === root)
        fixture.send("l", repeating: true)
        #expect(fixture.selectedItem === child)
        fixture.send("l")
        #expect(fixture.outline.isItemExpanded(child))
        #expect(fixture.selectedItem === child)
        fixture.send("l")
        #expect(fixture.selectedItem === grandchild)
        fixture.send("h")
        #expect(fixture.selectedItem === child)
        fixture.send("h")
        #expect(!fixture.outline.isItemExpanded(child))
        fixture.send("h")
        #expect(fixture.selectedItem === root)
        fixture.send("h")
        #expect(!fixture.outline.isItemExpanded(root))
    }

    @Test
    func recursiveBranchCommandsUseNativeExpansion() {
        let items = tree()
        let fixture = Fixture(items: items)
        defer { fixture.window.close() }
        fixture.outline.collapseItem(nil, collapseChildren: true)

        fixture.send("z")
        fixture.send("O", modifiers: .shift)
        #expect(fixture.outline.isItemExpanded(items[0]))
        #expect(fixture.outline.isItemExpanded(items[0].children[0]))
        #expect(!fixture.outline.isItemExpanded(items[1]))
        fixture.send("z")
        fixture.send("C", modifiers: .shift)
        #expect(!fixture.outline.isItemExpanded(items[0]))
        #expect(!fixture.outline.isItemExpanded(items[0].children[0]))
        fixture.send("z")
        fixture.send("R", modifiers: .shift)
        #expect(fixture.outline.isItemExpanded(items[0].children[0]))
        #expect(fixture.outline.isItemExpanded(items[1]))
        fixture.send("z")
        fixture.send("M", modifiers: .shift)
        #expect(!fixture.outline.isItemExpanded(items[0]))
        #expect(!fixture.outline.isItemExpanded(items[1]))
    }

    @Test
    func uppercaseBranchCommandsUseLeafParentAndKeepZeroDistinct() {
        let items = tree()
        let parent = items[0].children[0]
        let leaf = parent.children[0]
        let nested = PDFOutlineItem(id: "0.0.1", title: "Nested", destination: nil, pageIndex: nil, parent: parent)
        nested.children = [PDFOutlineItem(
            id: "0.0.1.0", title: "Nested detail", destination: nil, pageIndex: nil, parent: nested
        )]
        parent.children.append(nested)
        let rootLeaf = PDFOutlineItem(id: "2", title: "Root leaf", destination: nil, pageIndex: nil, parent: nil)
        let fixture = Fixture(items: items + [rootLeaf])
        defer { fixture.window.close() }

        fixture.send("z")
        fixture.send("R", modifiers: .capsLock)
        #expect(fixture.outline.isItemExpanded(parent))
        #expect(fixture.outline.isItemExpanded(items[1]))
        fixture.outline.collapseItem(nested, collapseChildren: true)
        fixture.outline.selectRowIndexes(IndexSet(integer: fixture.outline.row(forItem: leaf)), byExtendingSelection: false)

        fixture.send("z")
        fixture.send("0")
        #expect(!fixture.outline.isItemExpanded(nested))
        fixture.send("z")
        fixture.send("O", modifiers: .capsLock)
        #expect(fixture.outline.isItemExpanded(nested))
        fixture.send("z")
        fixture.send("C", modifiers: .capsLock)
        #expect(!fixture.outline.isItemExpanded(parent))
        #expect(fixture.outline.isItemExpanded(items[0]))

        fixture.send("z")
        fixture.send("M", modifiers: .capsLock)
        #expect(!fixture.outline.isItemExpanded(items[0]))
        #expect(!fixture.outline.isItemExpanded(items[1]))
        fixture.outline.selectRowIndexes(IndexSet(integer: fixture.outline.row(forItem: rootLeaf)), byExtendingSelection: false)
        fixture.send("z")
        fixture.send("O", modifiers: .capsLock)
        fixture.send("z")
        fixture.send("C", modifiers: .capsLock)
        #expect(fixture.outline.numberOfRows == 3)
        #expect(fixture.selectedItem === rootLeaf)
        #expect(fixture.window.firstResponder === fixture.outline)
    }

    @Test
    func optionArrowBranchCommandsRespectScopeModifiersAndPrefixes() {
        let items = tree()
        let fixture = Fixture(items: items)
        defer { fixture.window.close() }
        let left = "\u{f702}"
        let right = "\u{f703}"
        let parent = items[0].children[0]
        let leaf = parent.children[0]
        fixture.outline.collapseItem(nil, collapseChildren: true)

        fixture.send("2")
        fixture.send("g")
        fixture.send(right, keyCode: 124, modifiers: .option)
        #expect(fixture.outline.isItemExpanded(parent))
        #expect(!fixture.outline.isItemExpanded(items[1]))
        fixture.outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        fixture.send("g")
        #expect(fixture.outline.selectedRow == 1)
        fixture.send("g")
        #expect(fixture.outline.selectedRow == 0)

        fixture.outline.selectRowIndexes(IndexSet(integer: fixture.outline.row(forItem: leaf)), byExtendingSelection: false)
        fixture.send(left, keyCode: 123, modifiers: .option)
        #expect(!fixture.outline.isItemExpanded(parent))
        #expect(fixture.outline.isItemExpanded(items[0]))
        fixture.send(right, keyCode: 124, modifiers: .option, repeating: true)
        #expect(!fixture.outline.isItemExpanded(parent))

        fixture.send(right, keyCode: 124, modifiers: [.option, .shift])
        #expect(fixture.outline.isItemExpanded(parent))
        #expect(fixture.outline.isItemExpanded(items[1]))
        for excluded in [NSEvent.ModifierFlags.command, .control] {
            fixture.outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            fixture.send(left, keyCode: 123, modifiers: [.option, .shift, excluded])
            #expect(fixture.outline.isItemExpanded(items[1]))
        }

        fixture.send(left, keyCode: 123, modifiers: [.option, .shift])
        #expect(!fixture.outline.isItemExpanded(items[0]))
        #expect(!fixture.outline.isItemExpanded(items[1]))
        for excluded in [NSEvent.ModifierFlags.command, .control] {
            fixture.outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            fixture.send(right, keyCode: 124, modifiers: [.option, .shift, excluded])
            #expect(!fixture.outline.isItemExpanded(items[1]))
        }
        #expect(fixture.window.firstResponder === fixture.outline)
    }

    @Test(arguments: [CGFloat(160), CGFloat(198)])
    func pageCommandsMoveByHalfOrFullVisibleViewport(viewportHeight: CGFloat) {
        let fixture = Fixture()
        defer { fixture.window.close() }
        fixture.scrollView.setFrameSize(NSSize(width: 240, height: viewportHeight))
        fixture.scrollView.layoutSubtreeIfNeeded()
        func check(_ key: String, direction: Int, fraction: CGFloat = 1,
                   modifiers: NSEvent.ModifierFlags = [], keyCode: UInt16 = 0, repeating: Bool = false) {
            let before = fixture.outline.rect(ofRow: fixture.outline.selectedRow).midY
            let distance = fixture.outline.visibleRect.height * fraction
            fixture.send(key, keyCode: keyCode, modifiers: modifiers, repeating: repeating)
            let after = fixture.outline.rect(ofRow: fixture.outline.selectedRow).midY
            #expect(abs(after - before - CGFloat(direction) * distance) <= 36)
        }
        check("d", direction: 1, fraction: 0.5)
        check("u", direction: -1, fraction: 0.5)
        check("D", direction: 1, modifiers: .shift)
        check("U", direction: -1, modifiers: .shift)
        check("f", direction: 1)
        check("b", direction: -1)
        check(" ", direction: 1)
        check(" ", direction: 1, repeating: true)
        check("\u{f72c}", direction: -1, keyCode: 116)
        check("\u{f72d}", direction: 1, keyCode: 121)
    }

    @Test
    func nativeNavigationKeysStayInOutline() {
        let fixture = Fixture()
        defer { fixture.window.close() }
        fixture.send("\u{f701}", keyCode: 125)
        #expect(fixture.outline.selectedRow == 1)
        fixture.send("\u{f700}", keyCode: 126)
        #expect(fixture.outline.selectedRow == 0)
        fixture.send("\u{f72b}", keyCode: 119)
        #expect(fixture.outline.selectedRow == fixture.outline.numberOfRows - 1)
        fixture.send("\u{f729}", keyCode: 115)
        #expect(fixture.outline.selectedRow == 0)
        #expect(fixture.window.firstResponder === fixture.outline)
    }

    @Test
    func reloadAndFocusLossDiscardPendingInput() {
        let fixture = Fixture()
        defer { fixture.window.close() }
        fixture.send("7")
        fixture.send("g")
        fixture.outline.reloadData()
        fixture.outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        fixture.send("j")
        #expect(fixture.outline.selectedRow == 1)

        fixture.send("7")
        fixture.send("g")
        #expect(fixture.window.makeFirstResponder(fixture.reader))
        #expect(fixture.window.makeFirstResponder(fixture.outline))
        fixture.send("j")
        #expect(fixture.outline.selectedRow == 2)
        fixture.send("g")
        #expect(fixture.outline.selectedRow == 2)
        fixture.send("g")
        #expect(fixture.outline.selectedRow == 0)
    }

    @Test
    func appAndWindowDeactivationDiscardPendingInput() {
        let fixture = Fixture()
        defer { fixture.window.close() }
        for name in [NSApplication.willResignActiveNotification, NSWindow.didResignKeyNotification] {
            fixture.outline.selectRowIndexes(IndexSet(integer: 10), byExtendingSelection: false)
            fixture.send("9")
            fixture.send("g")
            NotificationCenter.default.post(name: name, object: name == NSWindow.didResignKeyNotification ? fixture.window : nil)
            fixture.send("j")
            #expect(fixture.outline.selectedRow == 11)
            fixture.send("g")
            #expect(fixture.outline.selectedRow == 11)
            fixture.send("g")
            #expect(fixture.outline.selectedRow == 0)
        }
    }

    @Test
    func commandModifiedKeysAndRepeatedCommandsDoNotActivateOrDismiss() {
        let fixture = Fixture()
        defer { fixture.window.close() }
        fixture.outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

        for (key, keyCode) in [("\r", UInt16(36)), ("\t", 48), ("t", 17), ("\u{1b}", 53)] {
            fixture.send(key, keyCode: keyCode, modifiers: .command)
            #expect(fixture.appState.isOutlineVisible)
            #expect(fixture.reader.currentPage === fixture.document.page(at: 0))
            #expect(fixture.window.makeFirstResponder(fixture.outline))
            fixture.send("3")
            fixture.send(key, keyCode: keyCode, repeating: true)
            #expect(fixture.appState.isOutlineVisible)
            #expect(fixture.reader.currentPage === fixture.document.page(at: 0))
            fixture.send("j")
        }
        #expect(fixture.outline.selectedRow == 13)
    }

    @Test
    func enterNavigatesAndRetainsOutlineFocus() {
        let fixture = Fixture()
        defer { fixture.window.close() }
        fixture.outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

        fixture.send("\r", keyCode: 36)
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        #expect(fixture.reader.currentPage === fixture.document.page(at: 1))
        #expect(fixture.appState.isOutlineVisible)
        #expect(fixture.window.firstResponder === fixture.outline)
    }

    @Test(arguments: [("\u{1b}", UInt16(53)), ("\t", 48), ("t", 17)])
    func dismissingOutlineReturnsFocusToReader(key: String, keyCode: UInt16) async throws {
        let fixture = Fixture()
        defer { fixture.window.close() }

        fixture.send(key, keyCode: keyCode)
        try await Task.sleep(for: .milliseconds(20))

        #expect(!fixture.appState.isOutlineVisible)
        #expect(fixture.window.firstResponder === fixture.reader)
    }

    private func tree() -> [PDFOutlineItem] {
        let root = PDFOutlineItem(id: "0", title: "Chapter", destination: nil, pageIndex: nil, parent: nil)
        let child = PDFOutlineItem(id: "0.0", title: "Section", destination: nil, pageIndex: nil, parent: root)
        child.children = [PDFOutlineItem(id: "0.0.0", title: "Detail", destination: nil, pageIndex: nil, parent: child)]
        root.children = [child]
        let second = PDFOutlineItem(id: "1", title: "Appendix", destination: nil, pageIndex: nil, parent: nil)
        second.children = [PDFOutlineItem(id: "1.0", title: "Index", destination: nil, pageIndex: nil, parent: second)]
        return [root, second]
    }

    @MainActor
    private final class Fixture {
        let appState: AppState
        let document = PDFDocument()
        let coordinator: PDFOutlineView.Coordinator
        let outline = PDFOutlineKeyView(frame: NSRect(x: 0, y: 0, width: 240, height: 160))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 160))
        let reader = VellumPDFView(frame: NSRect(x: 240, y: 0, width: 400, height: 320))
        let window: NSWindow

        var selectedItem: PDFOutlineItem? { outline.item(atRow: outline.selectedRow) as? PDFOutlineItem }

        init(items: [PDFOutlineItem]? = nil) {
            _ = NSApplication.shared
            appState = AppState(
                sessionDefaults: UserDefaults(suiteName: UUID().uuidString)!,
                keyboardController: KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false)
            )
            for index in 0..<2 {
                let page = PDFPage()
                page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
                document.insert(page, at: index)
            }
            let tab = PDFTab(url: nil, document: document)
            _ = appState.tabStore.openInNewTabs([tab])
            let document = self.document
            let outlineItems = items ?? (0..<30).map { index in
                PDFOutlineItem(
                    id: "\(index)", title: "Chapter \(index + 1)",
                    destination: PDFDestination(page: document.page(at: index == 0 ? 0 : 1)!, at: .zero),
                    pageIndex: index == 0 ? 0 : 1, parent: nil
                )
            }
            coordinator = PDFOutlineView.Coordinator(
                items: outlineItems, tabID: tab.id, documentID: ObjectIdentifier(document),
                appState: appState, language: .english
            )
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            outline.appState = appState
            outline.dataSource = coordinator
            outline.delegate = coordinator
            outline.headerView = nil
            outline.rowHeight = 30
            outline.intercellSpacing = NSSize(width: 0, height: 2)
            let column = NSTableColumn(identifier: PDFOutlineView.Coordinator.columnIdentifier)
            outline.addTableColumn(column)
            outline.outlineTableColumn = column
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.documentView = outline
            outline.reloadData()
            coordinator.restoreState(in: outline)
            window.contentView?.addSubview(scrollView)
            window.contentView?.addSubview(reader)
            reader.appState = appState
            reader.displayMode = .singlePage
            reader.document = document
            reader.layoutDocumentView()
            appState.activeReaderController = reader
            appState.readerWindow = window
            appState.isOutlineVisible = true
            window.orderFront(nil)
            scrollView.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            _ = window.makeFirstResponder(outline)
        }

        func send(
            _ key: String, keyCode: UInt16 = 0,
            modifiers: NSEvent.ModifierFlags = [], repeating: Bool = false
        ) {
            outline.keyDown(with: NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil,
                characters: key, charactersIgnoringModifiers: key, isARepeat: repeating, keyCode: keyCode
            )!)
        }
    }
}
