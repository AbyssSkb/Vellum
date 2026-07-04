@preconcurrency import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("App state reader controller")
struct AppStateReaderControllerTests {
    @Test
    func selectedTabActivatesReaderControllerAndRoutesCommands() {
        let appState = AppState()
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/sample.pdf"), document: nil)
        let reader = RecordingReaderController()

        _ = appState.tabStore.openInNewTabs([tab])
        appState.setActiveReaderController(reader, for: tab.id)

        appState.scrollBy(x: 3, y: -7)
        appState.moveByPage(2)
        appState.goToFirstPage()
        appState.goToLastPage()
        appState.goToPage(12)
        appState.jumpBack()
        appState.jumpForward()
        appState.beginSearch()
        appState.searchNext()
        appState.searchPrevious()
        appState.materializeSearchSelection()
        appState.copySelection()
        appState.highlightSelection()
        appState.explainHighlightSelection()
        appState.startAIConversation()
        appState.zoom(by: 1.25)
        appState.zoomToPageFit()
        appState.zoomToFit()

        #expect(reader.actions == [
            .scroll(x: 3, y: -7),
            .moveByPage(2),
            .firstPage,
            .lastPage,
            .goToPage(12),
            .jumpBack,
            .jumpForward,
            .beginSearch,
            .searchNext,
            .searchPrevious,
            .materializeSearchSelection,
            .copySelection,
            .highlightSelection,
            .explainHighlightSelection,
            .startAIConversation,
            .zoom(1.25),
            .zoomPageFit,
            .zoomFit
        ])
    }

    @Test
    func mismatchedTabDoesNotReplaceActiveReaderController() {
        let appState = AppState()
        let selectedTab = DocumentTab(url: URL(fileURLWithPath: "/tmp/selected.pdf"), document: nil)
        let otherTab = DocumentTab(url: URL(fileURLWithPath: "/tmp/other.pdf"), document: nil)
        let selectedReader = RecordingReaderController()
        let otherReader = RecordingReaderController()

        _ = appState.tabStore.openInNewTabs([selectedTab])
        appState.setActiveReaderController(selectedReader, for: selectedTab.id)
        appState.setActiveReaderController(otherReader, for: otherTab.id)

        appState.goToPage(5)

        #expect(selectedReader.actions == [.goToPage(5)])
        #expect(otherReader.actions == [])
    }

    @Test
    func changingSelectedTabClearsActiveReaderController() {
        let appState = AppState()
        let firstTab = DocumentTab(url: URL(fileURLWithPath: "/tmp/first.pdf"), document: nil)
        let secondTab = DocumentTab(url: URL(fileURLWithPath: "/tmp/second.pdf"), document: nil)
        let reader = RecordingReaderController()

        _ = appState.tabStore.openInNewTabs([firstTab, secondTab])
        appState.setActiveReaderController(reader, for: secondTab.id)
        appState.selectPreviousTab()
        appState.goToPage(7)

        #expect(appState.activeReaderController == nil)
        #expect(reader.actions == [])
    }

    @Test
    func activeReaderSnapshotIsSavedForSelectedTab() {
        let appState = AppState()
        let snapshot = ReaderSnapshot(
            pageIndex: 4,
            pointOnPage: NSPoint(x: 12, y: 34),
            scrollOrigin: NSPoint(x: 2, y: 8),
            scaleFactor: 1.5,
            autoScales: false
        )
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/sample.pdf"), document: nil)
        let reader = RecordingReaderController(snapshot: snapshot)

        _ = appState.tabStore.openInNewTabs([tab])
        appState.setActiveReaderController(reader, for: tab.id)
        appState.saveActiveReaderState()

        #expect(appState.snapshotForSelectedTab() == snapshot)
    }

    @Test
    func sessionSaveDoesNotCopyOldReaderSnapshotToNewlySelectedTab() {
        let appState = AppState()
        let firstSnapshot = ReaderSnapshot(
            pageIndex: 5,
            pointOnPage: NSPoint(x: 40, y: 80),
            scrollOrigin: NSPoint(x: 6, y: 12),
            scaleFactor: 1.75,
            autoScales: false
        )
        let firstTab = DocumentTab(url: URL(fileURLWithPath: "/tmp/first.pdf"), document: nil)
        let secondTab = DocumentTab(url: URL(fileURLWithPath: "/tmp/second.pdf"), document: nil)
        let firstReader = RecordingReaderController(snapshot: firstSnapshot)

        _ = appState.tabStore.openInNewTabs([firstTab])
        appState.setActiveReaderController(firstReader, for: firstTab.id)
        appState.saveActiveReaderState()

        _ = appState.tabStore.openInNewTabs([secondTab])
        appState.saveCurrentSession()

        #expect(appState.tabStore.tabs.first?.snapshot == firstSnapshot)
        #expect(appState.tabStore.tabs.last?.snapshot == nil)
    }

    @Test
    func conversationHistoryIsScopedToActiveDocument() {
        let appState = AppState()
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/current.pdf"), document: nil)
        let reader = RecordingReaderController(documentKey: "/tmp/current.pdf")

        _ = appState.tabStore.openInNewTabs([tab])
        appState.setActiveReaderController(reader, for: tab.id)
        appState.upsertAIConversationHistory(conversationHistoryItem(
            selectedText: "current",
            documentKey: "/tmp/current.pdf"
        ))
        appState.upsertAIConversationHistory(conversationHistoryItem(
            selectedText: "other",
            documentKey: "/tmp/other.pdf"
        ))

        appState.showAIConversationHistory()

        #expect(appState.isAIConversationHistoryPresented)
        #expect(appState.aiConversationHistory.map(\.selectedText) == ["current"])
    }

    @Test
    func explanationHistoryIncludesCurrentDocumentTransientAndAnnotationItems() {
        let appState = AppState()
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/current.pdf"), document: nil)
        let reader = RecordingReaderController(
            documentKey: "/tmp/current.pdf",
            aiExplanationHistory: [
                AIExplanationHistoryItem(
                    id: UUID(),
                    selectedText: "saved",
                    explanation: "Saved explanation",
                    fileName: "current.pdf",
                    documentKey: "/tmp/current.pdf",
                    pageNumbers: [2],
                    updatedAt: Date(timeIntervalSince1970: 2)
                )
            ]
        )

        _ = appState.tabStore.openInNewTabs([tab])
        appState.setActiveReaderController(reader, for: tab.id)
        appState.upsertAIExplanationHistory(AIExplanationHistoryItem(
            id: UUID(),
            selectedText: "transient",
            explanation: "Transient explanation",
            fileName: "current.pdf",
            documentKey: "/tmp/current.pdf",
            pageNumbers: [1],
            updatedAt: Date(timeIntervalSince1970: 3)
        ))
        appState.upsertAIExplanationHistory(AIExplanationHistoryItem(
            id: UUID(),
            selectedText: "other",
            explanation: "Other explanation",
            fileName: "other.pdf",
            documentKey: "/tmp/other.pdf",
            pageNumbers: [1],
            updatedAt: Date(timeIntervalSince1970: 4)
        ))

        appState.showAIExplanationHistory()

        #expect(appState.isAIExplanationHistoryPresented)
        #expect(appState.aiExplanationHistory.map(\.selectedText) == ["transient", "saved"])
    }

    @Test
    func emptyAIHistoryShowsReaderNotification() {
        let appState = AppState()
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/current.pdf"), document: nil)
        let reader = RecordingReaderController(documentKey: "/tmp/current.pdf")

        _ = appState.tabStore.openInNewTabs([tab])
        appState.setActiveReaderController(reader, for: tab.id)

        appState.showAIExplanationHistory()
        appState.showAIConversationHistory()

        #expect(!appState.isAIExplanationHistoryPresented)
        #expect(!appState.isAIConversationHistoryPresented)
        #expect(reader.notifications == [
            AppUILanguage.saved().text(.noAIExplanationsInFile),
            AppUILanguage.saved().text(.noAIConversationsInFile)
        ])
    }

    private func conversationHistoryItem(
        selectedText: String,
        documentKey: String
    ) -> AIConversationHistoryItem {
        AIConversationHistoryItem(
            id: UUID(),
            context: AIExplanationContext(
                selectedText: selectedText,
                currentParagraph: selectedText,
                nearbyText: selectedText,
                fileName: URL(fileURLWithPath: documentKey).lastPathComponent,
                documentKey: documentKey,
                pageNumbers: [1]
            ),
            messages: [AIConversationMessage(role: .user, content: selectedText)],
            updatedAt: Date()
        )
    }
}

@MainActor
private final class RecordingReaderController: ReaderController {
    var isAIInteractionActive = false
    var hasNavigableTextSelection = false
    var hasSearchTextTarget = false
    var isPageOverviewActive = false
    var documentKey: String?
    var aiExplanationHistory: [AIExplanationHistoryItem]
    private let savedSnapshot: ReaderSnapshot?
    private(set) var actions: [Action] = []
    private(set) var notifications: [String] = []

    init(
        snapshot: ReaderSnapshot? = nil,
        documentKey: String? = nil,
        aiExplanationHistory: [AIExplanationHistoryItem] = []
    ) {
        self.savedSnapshot = snapshot
        self.documentKey = documentKey
        self.aiExplanationHistory = aiExplanationHistory
    }

    func snapshot() -> ReaderSnapshot? {
        savedSnapshot
    }

    func focus() {
        actions.append(.focus)
    }

    func beginPageOverview() -> Bool {
        actions.append(.beginPageOverview)
        isPageOverviewActive = true
        return true
    }

    func movePageOverview(_ navigation: PageOverviewNavigation) -> Bool {
        actions.append(.movePageOverview(navigation))
        return true
    }

    func finishPageOverview() {
        actions.append(.finishPageOverview)
        isPageOverviewActive = false
    }

    func beginSearchCommand() {
        actions.append(.beginSearch)
    }

    func handleAIKeyEvent(_ event: NSEvent) -> Bool {
        false
    }

    func handleTextSelectionKeyEvent(_ event: NSEvent) -> Bool {
        false
    }

    func handleTextSelectionKey(_ rawKey: String, eventType: NSEvent.EventType) -> Bool {
        false
    }

    func vimDeleteHighlightsForSelection() -> Bool {
        false
    }

    func aiExplanationHistoryItems() -> [AIExplanationHistoryItem] {
        aiExplanationHistory
    }

    func showAINotification(_ message: String) {
        notifications.append(message)
    }

    func vimScroll(x: CGFloat, y: CGFloat) {
        actions.append(.scroll(x: x, y: y))
    }

    func vimMoveByPage(_ delta: Int) {
        actions.append(.moveByPage(delta))
    }

    func vimGoToFirstPage() {
        actions.append(.firstPage)
    }

    func vimGoToLastPage() {
        actions.append(.lastPage)
    }

    func vimGoToPage(_ pageNumber: Int) {
        actions.append(.goToPage(pageNumber))
    }

    func vimGoToDestination(_ destination: PDFDestination) {
        actions.append(.destination)
    }

    func vimJumpBack() {
        actions.append(.jumpBack)
    }

    func vimJumpForward() {
        actions.append(.jumpForward)
    }

    func vimSearchNext() {
        actions.append(.searchNext)
    }

    func vimSearchPrevious() {
        actions.append(.searchPrevious)
    }

    func vimMaterializeSearchSelection() {
        actions.append(.materializeSearchSelection)
    }

    func vimCopySelection() {
        actions.append(.copySelection)
    }

    func vimHighlightSelection(color: NSColor) {
        actions.append(.highlightSelection)
    }

    func vimExplainSelectedHighlight() {
        actions.append(.explainHighlightSelection)
    }

    func vimStartAIConversation() {
        actions.append(.startAIConversation)
    }

    func vimZoom(by factor: CGFloat) {
        actions.append(.zoom(factor))
    }

    func vimZoomToPageFit() {
        actions.append(.zoomPageFit)
    }

    func vimZoomToFit() {
        actions.append(.zoomFit)
    }

    enum Action: Equatable {
        case focus
        case beginPageOverview
        case movePageOverview(PageOverviewNavigation)
        case finishPageOverview
        case scroll(x: CGFloat, y: CGFloat)
        case moveByPage(Int)
        case firstPage
        case lastPage
        case goToPage(Int)
        case destination
        case jumpBack
        case jumpForward
        case beginSearch
        case searchNext
        case searchPrevious
        case materializeSearchSelection
        case copySelection
        case highlightSelection
        case explainHighlightSelection
        case startAIConversation
        case zoom(CGFloat)
        case zoomPageFit
        case zoomFit
    }
}
