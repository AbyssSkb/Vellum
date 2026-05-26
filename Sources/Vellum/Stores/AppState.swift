@preconcurrency import AppKit
import PDFKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private var tabStore = TabStore()
    @Published private(set) var isOutlineVisible = false
    @Published private(set) var outlineFocusGeneration = 0
    @Published private(set) var selectedHighlightColor: HighlightColor = .yellow

    private let documentCoordinator = DocumentCoordinator()

    weak var activePDFView: VellumPDFView?
    var keyMonitor: Any?
    var vimInput = VimInputController()
    let vimCommandDispatcher = VimCommandDispatcher()
    var heldKeyTimer: Timer?

    init() {
        installKeyMonitor()
        installOpenURLObserver()
    }

    var tabs: [PDFTab] {
        tabStore.tabs
    }

    var selectedTabID: PDFTab.ID? {
        tabStore.selectedTabID
    }

    var hasOpenDocuments: Bool {
        tabStore.hasOpenDocuments
    }

    var selectedTab: PDFTab? {
        tabStore.selectedTab
    }

    func setActivePDFView(_ view: VellumPDFView?, for tabID: PDFTab.ID) {
        guard tabID == selectedTabID else { return }
        activePDFView = view
    }

    func toggleOutlineSidebar() {
        guard hasOpenDocuments else {
            isOutlineVisible = false
            return
        }

        isOutlineVisible.toggle()
        if isOutlineVisible {
            outlineFocusGeneration += 1
        } else {
            focusReaderSoon()
        }
    }

    func focusOutlineSidebar() {
        guard isOutlineVisible else { return }
        outlineFocusGeneration += 1
    }

    func jumpToOutlineDestination(_ destination: PDFDestination) {
        activePDFView?.vimGoToDestination(destination)
    }

    func selectHighlightColor(_ color: HighlightColor) {
        selectedHighlightColor = color
        focusActivePDFViewSoon()
    }

    func cycleHighlightColor(preserveFocus: Bool = false) {
        selectedHighlightColor = selectedHighlightColor.next
        if !preserveFocus {
            focusActivePDFViewSoon()
        }
    }

    func selectTab(_ id: PDFTab.ID) {
        guard selectedTabID != id else { return }
        saveActiveReaderState()
        guard tabStore.selectTab(id) else { return }
        activePDFView = nil
        focusActivePDFViewSoon()
    }

    func openPanel(mode: PDFOpenMode = .currentTab) {
        PDFOpenPanelPresenter.present(mode: mode) { [weak self] urls in
            switch mode {
            case .currentTab:
                guard let url = urls.first else { return }
                self?.openInCurrentTab(url: url)
            case .newTabs:
                self?.openInNewTabs(urls: urls)
            }
        }
    }

    func open(urls: [URL]) {
        openInNewTabs(urls: urls)
    }

    func openInCurrentTab(url: URL) {
        saveActiveReaderState()

        guard let tab = documentCoordinator.openTab(for: url) else { return }

        tabStore.openInCurrentTab(tab)
        activePDFView = nil

        focusActivePDFViewSoon()
    }

    func openInNewTabs(urls: [URL]) {
        saveActiveReaderState()

        let newTabs = documentCoordinator.openTabs(for: urls)

        if tabStore.openInNewTabs(newTabs) {
            activePDFView = nil
            focusActivePDFViewSoon()
        }
    }

    func closeSelectedTab() {
        saveActiveReaderState()
        guard tabStore.closeSelectedTab() else { return }

        activePDFView = nil

        if !tabStore.hasOpenDocuments {
            isOutlineVisible = false
        }
        focusActivePDFViewSoon()
    }

    func restoreClosedPDFTab() {
        saveActiveReaderState()

        guard tabStore.restoreClosedPDFTab() else { return }
        activePDFView = nil
        focusActivePDFViewSoon()
    }

    func selectNextTab() {
        saveActiveReaderState()
        guard tabStore.selectNextTab() else { return }
        activePDFView = nil
        focusActivePDFViewSoon()
    }

    func selectPreviousTab() {
        saveActiveReaderState()
        guard tabStore.selectPreviousTab() else { return }
        activePDFView = nil
        focusActivePDFViewSoon()
    }

    func handleVimCommand(_ command: VimCommand) {
        vimCommandDispatcher.perform(command, on: self)
    }

    func snapshotForSelectedTab() -> ReaderSnapshot? {
        tabStore.snapshotForSelectedTab()
    }

    func saveSnapshot(_ snapshot: ReaderSnapshot, for tabID: PDFTab.ID) {
        tabStore.saveSnapshot(snapshot, for: tabID)
    }

    private func saveActiveReaderState() {
        guard let activePDFView,
              let selectedTabID,
              let snapshot = activePDFView.snapshot() else { return }
        saveSnapshot(snapshot, for: selectedTabID)
    }

    private func focusActivePDFViewSoon() {
        if isOutlineVisible {
            DispatchQueue.main.async { [weak self] in
                self?.outlineFocusGeneration += 1
            }
            return
        }
        focusReaderSoon()
    }

    private func focusReaderSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.activePDFView?.focus()
        }
    }
}

extension AppState: VimCommandTarget {
    func openPDFInCurrentTab() {
        openPanel(mode: .currentTab)
    }

    func openPDFInNewTabs() {
        openPanel(mode: .newTabs)
    }

    func scrollBy(x: CGFloat, y: CGFloat) {
        activePDFView?.vimScroll(x: x, y: y)
    }

    func moveByPage(_ delta: Int) {
        activePDFView?.vimMoveByPage(delta)
    }

    func goToFirstPage() {
        activePDFView?.vimGoToFirstPage()
    }

    func goToLastPage() {
        activePDFView?.vimGoToLastPage()
    }

    func goToPage(_ pageNumber: Int) {
        activePDFView?.vimGoToPage(pageNumber)
    }

    func jumpBack() {
        activePDFView?.vimJumpBack()
    }

    func jumpForward() {
        activePDFView?.vimJumpForward()
    }

    func highlightSelection() {
        activePDFView?.vimHighlightSelection(color: selectedHighlightColor.annotationColor)
    }

    func cycleHighlightColor() {
        cycleHighlightColor(preserveFocus: false)
    }

    func explainHighlightSelection() {
        activePDFView?.vimExplainSelectedHighlight()
    }

    func zoom(by factor: CGFloat) {
        activePDFView?.vimZoom(by: factor)
    }

    func zoomToPageFit() {
        activePDFView?.vimZoomToPageFit()
    }

    func zoomToFit() {
        activePDFView?.vimZoomToFit()
    }
}
