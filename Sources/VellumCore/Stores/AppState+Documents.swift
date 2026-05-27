import Foundation

extension AppState {
    func selectTab(_ id: PDFTab.ID) {
        guard selectedTabID != id else { return }
        saveActiveReaderState()
        guard tabStore.selectTab(id) else { return }
        activePDFView = nil
        focusActivePDFViewSoon()
    }

    public func openPanel(mode: PDFOpenMode = .currentTab) {
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

    public func closeSelectedTab() {
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

    public func selectNextTab() {
        saveActiveReaderState()
        guard tabStore.selectNextTab() else { return }
        activePDFView = nil
        focusActivePDFViewSoon()
    }

    public func selectPreviousTab() {
        saveActiveReaderState()
        guard tabStore.selectPreviousTab() else { return }
        activePDFView = nil
        focusActivePDFViewSoon()
    }
}
