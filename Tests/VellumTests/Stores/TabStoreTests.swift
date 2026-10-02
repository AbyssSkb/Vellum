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
    func reopeningFileInCurrentTabSelectsExistingTabAndKeepsReadingState() {
        var store = TabStore()
        var first = tab(named: "first")
        first.snapshot = readingSnapshot
        let second = tab(named: "second")
        let duplicate = tab(named: "first")
        _ = store.openInNewTabs([first, second])

        store.openInCurrentTab(duplicate)

        #expect(store.tabs.map(\.id) == [first.id, second.id])
        #expect(store.selectedTabID == first.id)
        #expect(store.selectedTab?.document === first.document)
        #expect(store.selectedTab?.snapshot == readingSnapshot)
    }

    @Test
    func repeatedFileInOpenBatchSelectsFirstInstance() {
        var store = TabStore()
        var first = tab(named: "first")
        first.snapshot = readingSnapshot
        let second = tab(named: "second")
        var duplicate = tab(named: "first")
        duplicate.url = URL(fileURLWithPath: "/tmp/subdir/../first.pdf")

        _ = store.openInNewTabs([first, second, duplicate])

        #expect(store.tabs.map(\.id) == [first.id, second.id])
        #expect(store.selectedTabID == first.id)
        #expect(store.selectedTab?.snapshot == readingSnapshot)
    }

    @Test
    func symlinkToOpenFileSelectsExistingTab() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("original.pdf")
        let linkURL = directory.appendingPathComponent("link.pdf")
        try Data().write(to: fileURL)
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: fileURL)
        var store = TabStore()
        let original = PDFTab(url: fileURL, document: PDFDocument())
        let duplicate = PDFTab(url: linkURL, document: PDFDocument())

        _ = store.openInNewTabs([original, duplicate])

        #expect(store.tabs.map(\.id) == [original.id])
        #expect(store.selectedTabID == original.id)
        #expect(store.tab(for: linkURL)?.id == original.id)
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
        let restoredTab = store.restoreClosedPDFTab(loader: { _ in second })

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
        let restoredTab = store.restoreClosedPDFTab(loader: { _ in
            Issue.record("Tabs without documents must not invoke the loader")
            return nil
        })

        #expect(closedTab)
        #expect(!restoredTab)
        #expect(store.tabs.isEmpty)
    }

    @Test
    func restoringFileAlreadyOpenSelectsExistingTabWithoutReloading() {
        var store = TabStore()
        var closed = tab(named: "first")
        closed.snapshot = .initial
        store.openInCurrentTab(closed)
        _ = store.closeSelectedTab()
        var reopened = tab(named: "first")
        reopened.snapshot = readingSnapshot
        let other = tab(named: "second")
        _ = store.openInNewTabs([reopened, other])

        let restored = store.restoreClosedPDFTab(loader: { _ in
            Issue.record("An open file must not be reloaded")
            return nil
        })

        #expect(restored)
        #expect(store.tabs.map(\.id) == [reopened.id, other.id])
        #expect(store.selectedTabID == reopened.id)
        #expect(store.selectedTab?.document === reopened.document)
        #expect(store.selectedTab?.snapshot == readingSnapshot)
    }

    @Test
    func restoringClosedFileReloadsLatestDiskContentAndKeepsSnapshot() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("changing.pdf")
        try writePDF(pageCount: 1, to: fileURL)
        let coordinator = PDFCoordinator()
        var original = try #require(coordinator.openTab(for: fileURL))
        original.snapshot = readingSnapshot
        var store = TabStore()
        store.openInCurrentTab(original)
        _ = store.closeSelectedTab()
        try writePDF(pageCount: 2, to: fileURL)

        let restored = store.restoreClosedPDFTab(loader: coordinator.openTab(for:))

        #expect(restored)
        #expect(store.selectedTab?.document !== original.document)
        #expect(store.selectedTab?.document?.pageCount == 2)
        #expect(store.selectedTab?.snapshot == readingSnapshot)
    }

    @Test
    func restoringMissingClosedFileDoesNotResurrectOldDocument() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("removed.pdf")
        try writePDF(pageCount: 1, to: fileURL)
        let coordinator = PDFCoordinator()
        let original = try #require(coordinator.openTab(for: fileURL))
        var store = TabStore()
        store.openInCurrentTab(original)
        _ = store.closeSelectedTab()
        try FileManager.default.removeItem(at: fileURL)

        let restored = store.restoreClosedPDFTab(loader: coordinator.openTab(for:))

        #expect(!restored)
        #expect(store.tabs.isEmpty)
    }

    @Test
    func closedHistoryDoesNotRetainPDFDocument() {
        var store = TabStore()
        weak var closedDocument: PDFDocument?
        autoreleasepool {
            let document = PDFDocument()
            closedDocument = document
            store.openInCurrentTab(PDFTab(url: URL(fileURLWithPath: "/tmp/closed.pdf"), document: document))
            _ = store.closeSelectedTab()
        }

        #expect(closedDocument == nil)
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

    @Test
    func restoringLegacySessionDeduplicatesCanonicalFilesAndPreservesFirstSnapshot() {
        var store = TabStore()
        var first = tab(named: "first")
        first.snapshot = readingSnapshot
        let second = tab(named: "second")
        var duplicate = tab(named: "first")
        duplicate.url = URL(fileURLWithPath: "/tmp/subdir/../first.pdf")

        let restored = store.restoreSessionTabs(
            [first, second, duplicate],
            selectedURLPath: duplicate.url?.path
        )

        #expect(restored)
        #expect(store.tabs.map(\.id) == [first.id, second.id])
        #expect(store.selectedTabID == first.id)
        #expect(store.selectedTab?.snapshot == readingSnapshot)
    }

    private var readingSnapshot: ReaderSnapshot {
        ReaderSnapshot(
            pageIndex: 1,
            pointOnPage: .init(x: 10, y: 20),
            scrollOrigin: .init(x: 2, y: 8),
            scaleFactor: 1.5,
            autoScales: false
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writePDF(pageCount: Int, to url: URL) throws {
        let document = PDFDocument()
        for index in 0..<pageCount {
            let page = PDFPage()
            page.setBounds(CGRect(x: 0, y: 0, width: 100, height: 100), for: .mediaBox)
            document.insert(page, at: index)
        }
        try #require(document.write(to: url))
    }

    private func tab(named name: String) -> PDFTab {
        PDFTab(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/\(name).pdf"),
            document: PDFDocument()
        )
    }
}
