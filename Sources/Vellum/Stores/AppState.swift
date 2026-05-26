@preconcurrency import AppKit
import PDFKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var tabs: [PDFTab] = []
    @Published private(set) var selectedTabID: PDFTab.ID?
    @Published private(set) var isOutlineVisible = false
    @Published private(set) var outlineFocusGeneration = 0
    @Published private(set) var selectedHighlightColor: HighlightColor = .yellow

    weak var activePDFView: VellumPDFView?
    var keyMonitor: Any?
    var keyState = VimKeyState()
    var heldKeyTimer: Timer?
    private var closedPDFTabHistory = ClosedPDFTabHistory()

    init() {
        installKeyMonitor()
        installOpenURLObserver()
    }

    var hasOpenDocuments: Bool {
        !tabs.isEmpty
    }

    var selectedTab: PDFTab? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
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
        guard selectedTabID != id, tabs.contains(where: { $0.id == id }) else { return }
        saveActiveReaderState()
        selectedTabID = id
        focusActivePDFViewSoon()
    }

    func openPanel(mode: PDFOpenMode = .currentTab) {
        PDFOpenPanelPresenter.present(mode: mode) { [weak self] urls in
            switch mode {
            case .currentTab:
                guard let url = urls.first else { return }
                self?.openInCurrentTab(url: url)
            case .newTabs:
                self?.openInNewTabs(urls: urls, reusingSelectedBlankTab: true)
            }
        }
    }

    func open(urls: [URL]) {
        openInNewTabs(urls: urls, reusingSelectedBlankTab: true)
    }

    func openInCurrentTab(url: URL) {
        saveActiveReaderState()

        guard let tab = PDFDocumentLoader.tab(for: url) else { return }

        if let index = selectedIndex {
            tabs[index] = tab
        } else {
            tabs = [tab]
        }
        selectedTabID = tab.id
        activePDFView = nil

        focusActivePDFViewSoon()
    }

    func openInNewTabs(urls: [URL], reusingSelectedBlankTab: Bool) {
        saveActiveReaderState()

        var openedDocument = false
        for url in urls {
            guard let tab = PDFDocumentLoader.tab(for: url) else { continue }

            tabs.append(tab)
            selectedTabID = tab.id
            openedDocument = true
        }

        if openedDocument {
            activePDFView = nil
            focusActivePDFViewSoon()
        }
    }

    func closeSelectedTab() {
        saveActiveReaderState()
        guard let selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }

        closedPDFTabHistory.remember(tabs[index])
        tabs.remove(at: index)
        activePDFView = nil

        if tabs.isEmpty {
            self.selectedTabID = nil
            isOutlineVisible = false
        } else {
            self.selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
        focusActivePDFViewSoon()
    }

    func restoreClosedPDFTab() {
        saveActiveReaderState()

        guard let tab = closedPDFTabHistory.restore() else { return }
        tabs.append(tab)
        selectedTabID = tab.id
        activePDFView = nil
        focusActivePDFViewSoon()
    }

    func selectNextTab() {
        guard let index = selectedIndex, !tabs.isEmpty else { return }
        selectTab(tabs[(index + 1) % tabs.count].id)
    }

    func selectPreviousTab() {
        guard let index = selectedIndex, !tabs.isEmpty else { return }
        selectTab(tabs[(index - 1 + tabs.count) % tabs.count].id)
    }

    func handleVimCommand(_ command: VimCommand) {
        switch command {
        case .open:
            openPanel(mode: .currentTab)
        case .openInNewTab:
            openPanel(mode: .newTabs)
        case .closeTab:
            closeSelectedTab()
        case .restoreClosedTab:
            restoreClosedPDFTab()
        case .nextTab:
            selectNextTab()
        case .previousTab:
            selectPreviousTab()
        case .scrollDown:
            activePDFView?.vimScroll(x: 0, y: -28)
        case .scrollUp:
            activePDFView?.vimScroll(x: 0, y: 28)
        case .largeScrollDown:
            activePDFView?.vimScroll(x: 0, y: -115)
        case .largeScrollUp:
            activePDFView?.vimScroll(x: 0, y: 115)
        case .scrollLeft:
            activePDFView?.vimScroll(x: -42, y: 0)
        case .scrollRight:
            activePDFView?.vimScroll(x: 42, y: 0)
        case .pageDown:
            activePDFView?.vimMoveByPage(1)
        case .pageUp:
            activePDFView?.vimMoveByPage(-1)
        case .firstPage:
            activePDFView?.vimGoToFirstPage()
        case .lastPage:
            activePDFView?.vimGoToLastPage()
        case .jumpToPage(let pageNumber):
            activePDFView?.vimGoToPage(pageNumber)
        case .jumpBack:
            activePDFView?.vimJumpBack()
        case .jumpForward:
            activePDFView?.vimJumpForward()
        case .toggleOutline:
            toggleOutlineSidebar()
        case .highlightSelection:
            activePDFView?.vimHighlightSelection(color: selectedHighlightColor.annotationColor)
        case .cycleHighlightColor:
            cycleHighlightColor()
        case .explainHighlightSelection:
            activePDFView?.vimExplainSelectedHighlight()
        case .zoomIn:
            activePDFView?.vimZoom(by: 1.04)
        case .zoomOut:
            activePDFView?.vimZoom(by: 1 / 1.04)
        case .zoomPageFit:
            activePDFView?.vimZoomToPageFit()
        case .zoomFit:
            activePDFView?.vimZoomToFit()
        }
    }

    func snapshotForSelectedTab() -> ReaderSnapshot? {
        selectedTab?.snapshot
    }

    func saveSnapshot(_ snapshot: ReaderSnapshot, for tabID: PDFTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].snapshot = snapshot
    }

    private var selectedIndex: Int? {
        guard let selectedTabID else { return nil }
        return tabs.firstIndex { $0.id == selectedTabID }
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
