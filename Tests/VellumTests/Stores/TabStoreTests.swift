import PDFKit
import Testing
@testable import VellumCore

@Suite("Tab store")
struct TabStoreTests {
    @Test
    func openingCurrentTabCreatesAndThenReplacesSelectedTab() {
        var store = TabStore()
        let first = tab(named: "first")
        let replacement = tab(named: "replacement")

        store.openInCurrentTab(first)
        #expect(store.tabs.map(\.id) == [first.id])
        #expect(store.selectedTabID == first.id)
        #expect(store.selectedTab == first)

        store.openInCurrentTab(replacement)
        #expect(store.tabs.map(\.id) == [replacement.id])
        #expect(store.selectedTabID == replacement.id)
        #expect(store.selectedTab == replacement)
    }

    @Test
    func openingNewTabsSelectsLastOpenedTab() {
        var store = TabStore()
        let first = tab(named: "first")
        let second = tab(named: "second")

        let openedTabs = store.openInNewTabs([first, second])

        #expect(openedTabs)
        #expect(store.tabs.map(\.id) == [first.id, second.id])
        #expect(store.selectedTabID == second.id)
        #expect(store.hasOpenTabs)
    }

    @Test
    func openingNoNewTabsIsIgnored() {
        var store = TabStore()

        let openedTabs = store.openInNewTabs([])

        #expect(!openedTabs)
        #expect(store.tabs.isEmpty)
        #expect(store.selectedTabID == nil)
    }

    @Test
    func selectingTabsWrapsForwardAndBackward() {
        var store = TabStore()
        let first = tab(named: "first")
        let second = tab(named: "second")
        let third = tab(named: "third")

        _ = store.openInNewTabs([first, second, third])

        let selectedNext = store.selectNextTab()
        #expect(store.selectedTabID == first.id)
        let selectedPrevious = store.selectPreviousTab()

        #expect(selectedNext)
        #expect(selectedPrevious)
        #expect(store.selectedTabID == third.id)
    }

    @Test
    func closingSelectedMiddleTabSelectsRightNeighbor() {
        var store = TabStore()
        let first = tab(named: "first")
        let second = tab(named: "second")
        let third = tab(named: "third")

        _ = store.openInNewTabs([first, second, third])
        let selectedSecond = store.selectTab(second.id)
        let closedTab = store.closeSelectedTab()

        #expect(selectedSecond)
        #expect(closedTab)
        #expect(store.tabs.map(\.id) == [first.id, third.id])
        #expect(store.selectedTabID == third.id)
    }

    @Test
    func closingNonSelectedTabKeepsCurrentSelection() {
        var store = TabStore()
        let first = tab(named: "first")
        let second = tab(named: "second")
        let third = tab(named: "third")

        _ = store.openInNewTabs([first, second, third])
        let selectedSecond = store.selectTab(second.id)
        let closedFirst = store.closeTab(first.id)

        #expect(selectedSecond)
        #expect(closedFirst)
        #expect(store.tabs.map(\.id) == [second.id, third.id])
        #expect(store.selectedTabID == second.id)
    }

    @Test
    func closingSpecificSelectedTabSelectsRightNeighbor() {
        var store = TabStore()
        let first = tab(named: "first")
        let second = tab(named: "second")
        let third = tab(named: "third")

        _ = store.openInNewTabs([first, second, third])
        let selectedSecond = store.selectTab(second.id)
        let closedSecond = store.closeTab(second.id)

        #expect(selectedSecond)
        #expect(closedSecond)
        #expect(store.tabs.map(\.id) == [first.id, third.id])
        #expect(store.selectedTabID == third.id)
    }

    @Test
    func restoringClosedTabAppendsAndSelectsIt() {
        var store = TabStore()
        let first = tab(named: "first")
        let second = tab(named: "second")

        _ = store.openInNewTabs([first, second])
        let closedTab = store.closeSelectedTab()
        let restoredTab = store.restoreClosedPDFTab()

        #expect(closedTab)
        #expect(restoredTab)
        #expect(store.tabs.map(\.id) == [first.id, second.id])
        #expect(store.selectedTabID == second.id)
    }

    @Test
    func tabsWithoutDocumentsAreNotRememberedForRestore() {
        var store = TabStore()
        let tabWithoutDocument = PDFTab(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/empty.pdf"),
            document: nil
        )

        store.openInCurrentTab(tabWithoutDocument)
        let closedTab = store.closeSelectedTab()
        let restoredTab = store.restoreClosedPDFTab()

        #expect(closedTab)
        #expect(!restoredTab)
        #expect(store.tabs.isEmpty)
    }

    @Test
    func snapshotIsSavedForMatchingTabOnly() {
        var store = TabStore()
        let first = tab(named: "first")
        let second = tab(named: "second")
        let snapshot = ReaderSnapshot(
            pageIndex: 4,
            pointOnPage: .init(x: 10, y: 20),
            scrollOrigin: .init(x: 2, y: 8),
            scaleFactor: 1.5,
            autoScales: false
        )

        _ = store.openInNewTabs([first, second])
        store.saveSnapshot(snapshot, for: first.id)

        #expect(store.tabs.first?.snapshot == snapshot)
        #expect(store.tabs.last?.snapshot == nil)
        #expect(store.snapshotForSelectedTab() == nil)
    }

    @Test
    func restoredSessionTabsSelectSavedURLPath() {
        var store = TabStore()
        let first = tab(named: "first")
        let second = tab(named: "second")

        let restored = store.restoreSessionTabs([first, second], selectedURLPath: second.url?.standardizedFileURL.path)

        #expect(restored)
        #expect(store.tabs.map(\.id) == [first.id, second.id])
        #expect(store.selectedTabID == second.id)
    }

    private func tab(named name: String) -> PDFTab {
        PDFTab(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/\(name).pdf"),
            document: PDFDocument()
        )
    }
}
