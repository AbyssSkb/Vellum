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
    func capsLockPreservesUppercaseTabAndOutlineCommands() {
        let fixture = Fixture(items: tree())
        defer { fixture.window.close() }
        let firstTabID = fixture.appState.selectedTabID
        let secondTab = PDFTab(url: nil, document: fixture.document)
        _ = fixture.appState.tabStore.openInNewTabs([secondTab])
        _ = fixture.appState.tabStore.selectTab(firstTabID!)
        let expandedIDs = fixture.outline.expandedIDs
        let selectedRow = fixture.outline.selectedRow

        fixture.send("L", modifiers: .capsLock)
        #expect(fixture.appState.selectedTabID == secondTab.id)
        fixture.send("H", modifiers: .capsLock)
        #expect(fixture.appState.selectedTabID == firstTabID)
        #expect(fixture.outline.expandedIDs == expandedIDs)
        #expect(fixture.outline.selectedRow == selectedRow)
        #expect(fixture.appState.isOutlineVisible)

        fixture.send("G", modifiers: .capsLock)
        #expect(fixture.outline.selectedRow == fixture.outline.numberOfRows - 1)
        fixture.send("T", modifiers: .capsLock)
        #expect(fixture.appState.isTabSwitcherPresented)
        #expect(fixture.appState.isOutlineVisible)
    }

    @Test(arguments: [false, true])
    func hierarchyKeysFoldLogicalCursorAndMoveToNextVisibleRow(arrows: Bool) {
        let items = tree()
        let fixture = Fixture(items: items)
        defer { fixture.window.close() }
        let root = items[0]
        let child = root.children[0]
        let grandchild = child.children[0]
        let closeKey = arrows ? "\u{f702}" : "h"
        let openKey = arrows ? "\u{f703}" : "l"
        let closeCode: UInt16 = arrows ? 123 : 0
        let openCode: UInt16 = arrows ? 124 : 0
        fixture.outline.collapseItem(root, collapseChildren: true)

        fixture.send(openKey, keyCode: openCode)
        #expect(fixture.outline.isItemExpanded(root))
        #expect(fixture.selectedItem === root)
        fixture.send(openKey, keyCode: openCode, repeating: true)
        #expect(fixture.selectedItem === child)
        fixture.send(openKey, keyCode: openCode)
        #expect(fixture.outline.isItemExpanded(child))
        #expect(fixture.selectedItem === child)
        fixture.send(openKey, keyCode: openCode)
        #expect(fixture.selectedItem === grandchild)
        fixture.send(closeKey, keyCode: closeCode)
        #expect(fixture.selectedItem === child)
        #expect(!fixture.outline.isItemExpanded(child))
        #expect(fixture.outline.selectedFoldItem === grandchild)
        fixture.send(closeKey, keyCode: closeCode)
        #expect(fixture.selectedItem === root)
        #expect(!fixture.outline.isItemExpanded(root))
        #expect(fixture.outline.selectedFoldItem === grandchild)
        fixture.send(openKey, keyCode: openCode)
        #expect(fixture.selectedItem === child)
        #expect(!fixture.outline.isItemExpanded(child))
        fixture.send(openKey, keyCode: openCode)
        #expect(fixture.selectedItem === grandchild)
        fixture.send(openKey, keyCode: openCode)
        #expect(fixture.selectedItem === items[1])
        #expect(fixture.outline.selectedFoldItem === items[1])
        #expect(fixture.outline.foldLevel == 1)
    }

    @Test(arguments: [false, true])
    func hierarchyCountsAndAutoRepeatPreserveFoldPathUntilNavigation(arrows: Bool) {
        let items = deepTree()
        let fixture = Fixture(items: items)
        defer { fixture.window.close() }
        let parent = items[0].children[0]
        let leaf = parent.children[0].children[0]
        let closeKey = arrows ? "\u{f702}" : "h"
        let openKey = arrows ? "\u{f703}" : "l"
        let closeCode: UInt16 = arrows ? 123 : 0
        let openCode: UInt16 = arrows ? 124 : 0
        fixture.sendKeys("zR")
        fixture.outline.selectRowIndexes(IndexSet(integer: fixture.outline.row(forItem: leaf)), byExtendingSelection: false)

        fixture.send("2")
        fixture.send(closeKey, keyCode: closeCode)
        #expect(fixture.outline.expandedIDs == ["0", "1"])
        #expect(fixture.selectedItem === parent)
        #expect(fixture.outline.selectedFoldItem === leaf)
        fixture.send(closeKey, keyCode: closeCode, repeating: true)
        #expect(fixture.outline.expandedIDs == ["1"])
        #expect(fixture.selectedItem === items[0])
        fixture.send(closeKey, keyCode: closeCode, repeating: true)
        #expect(fixture.outline.expandedIDs == ["1"])
        fixture.send("3")
        fixture.send(openKey, keyCode: openCode)
        #expect(fixture.selectedItem === leaf)
        #expect(fixture.outline.isItemExpanded(parent.children[0]))
        fixture.send("2")
        fixture.send(openKey, keyCode: openCode)
        #expect(fixture.selectedItem === items[1].children[0])
        fixture.send(openKey, keyCode: openCode, repeating: true)
        #expect(fixture.selectedItem === items[1].children[0])
        #expect(fixture.outline.selectedFoldItem === items[1].children[0])
        #expect(fixture.outline.foldLevel == 3)
    }

    @Test(arguments: ["9", String(repeating: "9", count: 30)])
    func expansionCountsIncludeNewlyVisibleRowsAndClampAtLastLeaf(count: String) {
        let items = deepTree()
        let fixture = Fixture(items: items)
        defer { fixture.window.close() }
        fixture.sendKeys("zM")

        fixture.sendKeys(count + "l")
        #expect(fixture.selectedItem === items[1].children[0])
        #expect(fixture.outline.expandedIDs == ["0", "0.0", "0.0.0", "1"])
        #expect(fixture.outline.foldLevel == 0)
        #expect(fixture.window.firstResponder === fixture.outline)
    }

    @Test
    func hierarchyKeysMoveBetweenRootLeavesAndClampAtBoundaries() {
        let fixture = Fixture()
        defer { fixture.window.close() }

        fixture.sendKeys("hl")
        #expect(fixture.outline.selectedRow == 1)
        fixture.send("l", repeating: true)
        #expect(fixture.outline.selectedRow == 2)
        fixture.sendKeys("3h")
        #expect(fixture.outline.selectedRow == 2)
        fixture.sendKeys("G")
        fixture.sendKeys(String(repeating: "9", count: 30) + "l")
        #expect(fixture.outline.selectedRow == fixture.outline.numberOfRows - 1)
        fixture.sendKeys("h")
        #expect(fixture.outline.selectedRow == fixture.outline.numberOfRows - 1)
        #expect(fixture.outline.expandedIDs.isEmpty)
    }

    @Test
    func recursiveFoldCommandsOpenClosedBranchesAndPreserveHiddenDescendants() {
        let items = deepTree()
        let fixture = Fixture(items: items)
        defer { fixture.window.close() }
        fixture.outline.collapseItem(nil, collapseChildren: true)

        fixture.sendKeys("zO")
        #expect(fixture.outline.isItemExpanded(items[0]))
        #expect(fixture.outline.isItemExpanded(items[0].children[0]))
        #expect(fixture.outline.isItemExpanded(items[0].children[0].children[0]))
        #expect(!fixture.outline.isItemExpanded(items[1]))
        fixture.sendKeys("zC")
        #expect(!fixture.outline.isItemExpanded(items[0]))
        #expect(fixture.outline.expandedIDs == ["0.0", "0.0.0"])
        fixture.sendKeys("zo")
        #expect(fixture.outline.isItemExpanded(items[0].children[0].children[0]))
        fixture.sendKeys("zR")
        #expect(fixture.outline.isItemExpanded(items[0].children[0]))
        #expect(fixture.outline.isItemExpanded(items[1]))
        fixture.sendKeys("zM")
        #expect(fixture.outline.expandedIDs.isEmpty)
        #expect(!fixture.outline.isItemExpanded(items[0]))
        #expect(!fixture.outline.isItemExpanded(items[1]))
    }

    @Test
    func uppercaseFoldCommandsRespectCursorPathAndKeepZeroDistinct() {
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
        #expect(!fixture.outline.isItemExpanded(nested))
        fixture.send("z")
        fixture.send("C", modifiers: .capsLock)
        #expect(!fixture.outline.isItemExpanded(parent))
        #expect(!fixture.outline.isItemExpanded(items[0]))
        #expect(fixture.outline.isItemExpanded(items[1]))
        #expect(fixture.outline.selectedFoldItem === leaf)

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
        #expect(fixture.outline.foldLevel == 1)
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
        #expect(fixture.outline.foldLevel == 1)
    }

    @Test
    func singleLayerFoldCommandsFollowLogicalCursorThroughHiddenAncestors() {
        let items = deepTree()
        let parent = items[0].children[0]
        let nested = parent.children[0]
        let leaf = nested.children[0]
        let fixture = Fixture(items: items)
        defer { fixture.window.close() }

        fixture.sendKeys("zR")
        fixture.outline.selectRowIndexes(IndexSet(integer: fixture.outline.row(forItem: leaf)), byExtendingSelection: false)
        for ancestor in [nested, parent, items[0]] {
            fixture.sendKeys("zc")
            #expect(!fixture.outline.expandedIDs.contains(ancestor.id))
            #expect(fixture.selectedItem === ancestor)
            #expect(fixture.outline.selectedFoldItem === leaf)
        }
        #expect(fixture.outline.isItemExpanded(items[1]))
        for ancestor in [items[0], parent, nested] {
            fixture.sendKeys("zo")
            #expect(fixture.outline.isItemExpanded(ancestor))
            #expect(fixture.outline.selectedFoldItem === leaf)
        }
        #expect(fixture.selectedItem === leaf)
        #expect(fixture.outline.foldLevel == 3)
        #expect(fixture.window.firstResponder === fixture.outline)
    }

    @Test(arguments: [("2zc", "2zo", 2), ("3zc", "3zo", 3)])
    func foldCountsBeforePrefixOpenAndCloseLogicalPath(close: String, open: String, depth: Int) {
        let items = deepTree()
        let fixture = Fixture(items: items)
        defer { fixture.window.close() }
        let path = [items[0], items[0].children[0], items[0].children[0].children[0]]
        let leaf = path[2].children[0]
        fixture.sendKeys("zR")
        fixture.outline.selectRowIndexes(IndexSet(integer: fixture.outline.row(forItem: leaf)), byExtendingSelection: false)

        fixture.sendKeys(close)
        #expect(fixture.outline.expandedIDs == Set(path.prefix(3 - depth).map(\.id) + [items[1].id]))
        #expect(fixture.outline.selectedFoldItem === leaf)
        fixture.sendKeys(open)
        #expect(fixture.outline.expandedIDs == Set(path.map(\.id) + [items[1].id]))
        #expect(fixture.selectedItem === leaf)
        #expect(fixture.outline.foldLevel == 3)
    }

    @Test(arguments: ["z2r", "z3m", "z2o", "z2c", "2z3O", "z0c"])
    func countsAfterFoldPrefixAreConsumedWithoutChangingState(command: String) {
        let items = deepTree()
        let fixture = Fixture(items: items)
        defer { fixture.window.close() }
        let parent = items[0].children[0]
        let leaf = parent.children[0].children[0]
        fixture.outline.expandItem(items[0], expandChildren: true)
        fixture.outline.collapseItem(parent)
        fixture.outline.selectFoldItem(leaf)
        let expandedIDs = fixture.outline.expandedIDs

        fixture.sendKeys(command)
        #expect(fixture.outline.foldLevel == 1)
        #expect(fixture.outline.expandedIDs == expandedIDs)
        #expect(fixture.selectedItem === parent)
        #expect(fixture.outline.selectedFoldItem === leaf)
        fixture.sendKeys("zo")
        #expect(fixture.outline.isItemExpanded(parent))
        #expect(fixture.selectedItem === leaf)
    }

    @Test
    func recursiveCommandsLeaveOtherBranchesAndOffPathDescendantsUnchanged() {
        let items = deepTree()
        let parent = items[0].children[0]
        let nested = parent.children[0]
        let sibling = PDFOutlineItem(id: "0.0.1", title: "Sibling", destination: nil, pageIndex: nil, parent: parent)
        sibling.children = [PDFOutlineItem(id: "0.0.1.0", title: "Sibling detail", destination: nil, pageIndex: nil, parent: sibling)]
        parent.children.append(sibling)
        let fixture = Fixture(items: items)
        defer { fixture.window.close() }

        fixture.sendKeys("zO")
        #expect(fixture.outline.expandedIDs == ["0", "1"])
        fixture.sendKeys("zR")
        fixture.outline.collapseItem(sibling)
        fixture.sendKeys("zO")
        #expect(!fixture.outline.expandedIDs.contains(sibling.id))
        fixture.outline.expandItem(sibling)
        let leaf = nested.children[0]
        fixture.outline.selectRowIndexes(IndexSet(integer: fixture.outline.row(forItem: leaf)), byExtendingSelection: false)
        fixture.sendKeys("zC")
        #expect(fixture.outline.expandedIDs == [sibling.id, items[1].id])
        #expect(fixture.selectedItem === items[0])
        fixture.sendKeys("zO")
        #expect(fixture.outline.expandedIDs == ["0", "0.0", "0.0.0", "0.0.1", "1"])
        #expect(fixture.selectedItem === leaf)
    }

    @Test
    func closingSkipsRememberedOpenDescendantsBelowAClosedFold() {
        let items = deepTree()
        let fixture = Fixture(items: items)
        defer { fixture.window.close() }
        let parent = items[0].children[0]
        let nested = parent.children[0]
        let leaf = nested.children[0]
        fixture.sendKeys("zR")
        fixture.outline.selectRowIndexes(IndexSet(integer: fixture.outline.row(forItem: leaf)), byExtendingSelection: false)
        fixture.outline.collapseItem(parent)
        fixture.outline.selectFoldItem(leaf)

        fixture.sendKeys("zc")
        #expect(!fixture.outline.expandedIDs.contains(items[0].id))
        #expect(fixture.outline.expandedIDs.contains(nested.id))
        fixture.sendKeys("2zo")
        #expect(fixture.outline.isItemExpanded(nested))
        #expect(fixture.selectedItem === leaf)
    }

    @Test
    func globalFoldCommandsStepThroughUnevenTreeDepthAndClamp() {
        let items = deepTree()
        let fixture = Fixture(items: items)
        defer { fixture.window.close() }

        for (key, depth) in [("m", 0), ("r", 1), ("r", 2), ("r", 3), ("r", 3),
                             ("m", 2), ("m", 1), ("m", 0), ("m", 0)] {
            fixture.send("z")
            fixture.send(key)
            #expect(fixture.outline.foldLevel == depth)
            #expect(fixture.outline.isItemExpanded(items[0]) == (depth > 0))
            #expect(fixture.outline.isItemExpanded(items[1]) == (depth > 0))
            #expect(fixture.outline.isItemExpanded(items[0].children[0]) == (depth > 1))
            #expect(fixture.outline.isItemExpanded(items[0].children[0].children[0]) == (depth > 2))
            #expect(fixture.selectedItem === items[0])
            #expect(fixture.window.firstResponder === fixture.outline)
        }
    }

    @Test
    func globalDepthUsesStoredLevelAndResetsManualOverrides() {
        let items = deepTree()
        let parent = items[0].children[0]
        let nested = parent.children[0]
        let fixture = Fixture(items: items)
        defer { fixture.window.close() }

        fixture.sendKeys("zM")
        fixture.sendKeys("zO")
        #expect(fixture.outline.foldLevel == 0)
        #expect(fixture.outline.isItemExpanded(nested))
        fixture.sendKeys("zr")
        #expect(fixture.outline.foldLevel == 1)
        #expect(fixture.outline.isItemExpanded(items[0]))
        #expect(fixture.outline.isItemExpanded(items[1]))
        #expect(!fixture.outline.isItemExpanded(parent))

        fixture.sendKeys("zR")
        fixture.sendKeys("zc")
        #expect(!fixture.outline.isItemExpanded(items[0]))
        #expect(fixture.outline.foldLevel == 3)
        fixture.sendKeys("zm")
        #expect(fixture.outline.foldLevel == 2)
        #expect(fixture.outline.isItemExpanded(parent))
        #expect(!fixture.outline.isItemExpanded(nested))
        fixture.outline.selectRowIndexes(IndexSet(integer: fixture.outline.row(forItem: items[1])), byExtendingSelection: false)
        fixture.sendKeys("zc")
        #expect(!fixture.outline.isItemExpanded(items[1]))
        fixture.sendKeys("zm")
        #expect(fixture.outline.foldLevel == 1)
        #expect(fixture.outline.isItemExpanded(items[1]))
        #expect(!fixture.outline.isItemExpanded(parent))
        #expect(fixture.window.firstResponder === fixture.outline)
    }

    @Test
    func maximumReducePreservesOverridesButOpenAllAndMinimumIncreaseResetThem() {
        let items = deepTree()
        let fixture = Fixture(items: items)
        defer { fixture.window.close() }

        fixture.sendKeys("zR")
        fixture.outline.selectRowIndexes(IndexSet(integer: fixture.outline.row(forItem: items[1])), byExtendingSelection: false)
        fixture.sendKeys("zc")
        fixture.sendKeys("zr")
        #expect(fixture.outline.foldLevel == 3)
        #expect(!fixture.outline.isItemExpanded(items[1]))
        fixture.sendKeys("zR")
        #expect(fixture.outline.isItemExpanded(items[1]))
        fixture.sendKeys("zM")
        fixture.sendKeys("zO")
        #expect(fixture.outline.foldLevel == 0)
        #expect(fixture.outline.isItemExpanded(items[1]))
        fixture.sendKeys("zm")
        #expect(fixture.outline.foldLevel == 0)
        #expect(fixture.outline.expandedIDs.isEmpty)
    }

    @Test
    func globalCountsAndOverflowClampWithoutChangingLogicalCursor() {
        let items = deepTree()
        let fixture = Fixture(items: items)
        defer { fixture.window.close() }
        let leaf = items[0].children[0].children[0].children[0]
        fixture.sendKeys("zR")
        fixture.outline.selectRowIndexes(IndexSet(integer: fixture.outline.row(forItem: leaf)), byExtendingSelection: false)
        fixture.sendKeys("2zm")
        #expect(fixture.outline.foldLevel == 1)
        #expect(fixture.selectedItem === items[0].children[0])
        #expect(fixture.outline.selectedFoldItem === leaf)
        fixture.sendKeys("2zr")
        #expect(fixture.outline.foldLevel == 3)
        #expect(fixture.selectedItem === leaf)
        fixture.sendKeys("3zm")
        #expect(fixture.outline.foldLevel == 0)
        #expect(fixture.selectedItem === items[0])
        let overflowingCount = String(repeating: "9", count: 30)
        fixture.sendKeys(overflowingCount + "zr")
        #expect(fixture.outline.foldLevel == 3)
        #expect(fixture.selectedItem === leaf)
        fixture.sendKeys(overflowingCount + "zc")
        #expect(fixture.outline.expandedIDs == [items[1].id])
        fixture.sendKeys(overflowingCount + "zo")
        #expect(fixture.selectedItem === leaf)
        fixture.sendKeys(overflowingCount + "zm")
        #expect(fixture.outline.foldLevel == 0)
        #expect(fixture.outline.expandedIDs.isEmpty)
        #expect(fixture.outline.selectedFoldItem === leaf)
    }

    @Test
    func explicitSelectionAndNavigationReplaceLogicalFoldCursor() {
        let items = deepTree()
        let fixture = Fixture(items: items)
        defer { fixture.window.close() }
        let leaf = items[0].children[0].children[0].children[0]
        fixture.sendKeys("zR")
        fixture.outline.selectRowIndexes(IndexSet(integer: fixture.outline.row(forItem: leaf)), byExtendingSelection: false)
        fixture.sendKeys("zC")
        #expect(fixture.outline.selectedFoldItem === leaf)
        fixture.outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        #expect(fixture.outline.selectedFoldItem === items[0])
        fixture.sendKeys("zozo")
        #expect(fixture.outline.isItemExpanded(items[0]))
        #expect(!fixture.outline.isItemExpanded(items[0].children[0]))

        fixture.sendKeys("zR")
        fixture.outline.selectRowIndexes(IndexSet(integer: fixture.outline.row(forItem: leaf)), byExtendingSelection: false)
        fixture.sendKeys("zC")
        fixture.outline.expandItem(items[0])
        #expect(fixture.outline.selectedFoldItem === items[0])
        fixture.sendKeys("zO")
        #expect(!fixture.outline.isItemExpanded(items[0].children[0]))

        fixture.sendKeys("zR")
        fixture.outline.selectRowIndexes(IndexSet(integer: fixture.outline.row(forItem: leaf)), byExtendingSelection: false)
        fixture.sendKeys("zM")
        fixture.sendKeys("jzo")
        #expect(fixture.outline.selectedFoldItem === items[1])
        #expect(!fixture.outline.isItemExpanded(items[0]))
        #expect(fixture.outline.isItemExpanded(items[1]))
        #expect(fixture.outline.foldLevel == 0)
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
        #expect(fixture.outline.selectedRow == 11)
    }

    @Test
    func enterNavigatesAndReturnsToReaderWithOutlineVisible() async throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        fixture.outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

        fixture.send("\r", keyCode: 36)
        try await Task.sleep(for: .milliseconds(30))

        #expect(fixture.reader.currentPage === fixture.document.page(at: 1))
        #expect(fixture.appState.isOutlineVisible)
        #expect(fixture.window.firstResponder === fixture.reader)
    }

    @Test
    func tClosesOutlineAndReturnsFocusToReader() async throws {
        let fixture = Fixture()
        defer { fixture.window.close() }

        fixture.send("t", keyCode: 17)
        try await Task.sleep(for: .milliseconds(20))

        #expect(!fixture.appState.isOutlineVisible)
        let readerIsFocused = fixture.window.firstResponder === fixture.reader
        #expect(readerIsFocused)
    }

    @Test
    func escapeReturnsToReaderAndKeepsOutlineAndCursor() async throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        fixture.outline.selectRowIndexes(IndexSet(integer: 5), byExtendingSelection: false)
        fixture.send("\u{1b}", keyCode: 53)
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.appState.isOutlineVisible)
        #expect(fixture.window.firstResponder === fixture.reader)
        #expect(fixture.outline.selectedRow == 5)
    }

    @Test(arguments: ["4", "g", "z"])
    func escapeFirstCancelsOutlinePrefixThenReturnsToReader(prefix: String) async throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        fixture.send(prefix)
        fixture.send("\u{1b}", keyCode: 53)
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.appState.isOutlineVisible)
        #expect(fixture.window.firstResponder === fixture.outline)
        fixture.send("j")
        #expect(fixture.outline.selectedRow == 1)
        fixture.send("\u{1b}", keyCode: 53)
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.window.firstResponder === fixture.reader)
        #expect(fixture.appState.isOutlineVisible)
    }

    @Test
    func tabWaitsForReleaseAndTransfersFocusWithoutClosingOutline() async throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        fixture.outline.selectRowIndexes(IndexSet(integer: 5), byExtendingSelection: false)
        fixture.send("\t", keyCode: 48)
        #expect(fixture.window.firstResponder === fixture.outline)
        #expect(fixture.appState.isOutlineVisible)
        fixture.send("\t", keyCode: 48, type: .keyUp)
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.window.firstResponder === fixture.reader)
        #expect(fixture.appState.isOutlineVisible)
        #expect(fixture.outline.selectedRow == 5)
    }

    private func deepTree() -> [PDFOutlineItem] {
        let items = tree()
        let detail = items[0].children[0].children[0]
        detail.children = [PDFOutlineItem(
            id: "0.0.0.0", title: "Deep detail", destination: nil, pageIndex: nil, parent: detail
        )]
        return items
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
            window = OutlineKeyboardWindow(
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
            modifiers: NSEvent.ModifierFlags = [], repeating: Bool = false,
            type: NSEvent.EventType = .keyDown
        ) {
            let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil,
                characters: key, charactersIgnoringModifiers: key, isARepeat: repeating, keyCode: keyCode
            )!
            if type == .keyDown { outline.keyDown(with: event) }
            else { outline.keyUp(with: event) }
        }

        func sendKeys(_ keys: String) {
            for key in keys { send(String(key)) }
        }
    }
}

// Keep focus ownership deterministic without requiring WindowServer activation.
@MainActor
private final class OutlineKeyboardWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
