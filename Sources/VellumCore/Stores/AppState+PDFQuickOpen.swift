@preconcurrency import AppKit

extension AppState {
    public func showPDFQuickOpen() {
        guard !isPDFQuickOpenPresented, NSApp?.modalWindow == nil,
              readerWindow?.attachedSheet == nil else { return }
        if let readerWindow, !readerWindow.isKeyWindow { readerWindow.makeKeyAndOrderFront(nil) }
        saveActiveReaderState()
        rememberFocusBeforeSwitcher()
        isTabSwitcherPresented = false
        isAIConversationHistoryPresented = false
        isAIExplanationHistoryPresented = false
        isHighlightsPresented = false
        highlightItems = []
        isPDFQuickOpenPresented = true
        pdfQuickOpenSearch.beginSearching()
    }

    func hidePDFQuickOpen() {
        guard isPDFQuickOpenPresented else { return }
        isPDFQuickOpenPresented = false
        pdfQuickOpenSearch.endSearching()
        restoreFocusAfterSwitcher()
    }

    func openPDFQuickOpenResult(_ url: URL) {
        guard isPDFQuickOpenPresented, pdfQuickOpenSearch.results.contains(url) else { return }
        isPDFQuickOpenPresented = false
        pdfQuickOpenSearch.endSearching()
        switch AppPreferences.defaultPDFOpenMode() {
        case .currentTab:
            openInCurrentTab(url: url)
        case .newTabs:
            openInNewTabs(urls: [url])
        }
        restoreFocusAfterSwitcher()
    }
}
