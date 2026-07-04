import Foundation

extension AppState {
    func selectTab(_ id: DocumentTab.ID) {
        guard selectedTabID != id else { return }
        saveActiveReaderState()
        guard tabStore.selectTab(id) else { return }
        saveCurrentSession()
        prepareForSelectedReaderChange()
    }

    func selectTabFromSwitcher(_ id: DocumentTab.ID) {
        isTabSwitcherPresented = false
        selectTab(id)
        focusActiveReaderSoon()
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
        saveCurrentSession()
        prepareForSelectedReaderChange()
    }

    func openInNewTabs(urls: [URL]) {
        saveActiveReaderState()

        let newTabs = documentCoordinator.openTabs(for: urls)

        if tabStore.openInNewTabs(newTabs) {
            saveCurrentSession()
            prepareForSelectedReaderChange()
        }
    }

    public func closeSelectedTab() {
        guard let selectedTabID else { return }
        closeTab(selectedTabID)
    }

    func closeTab(_ id: DocumentTab.ID) {
        let previousSelectedTabID = selectedTabID
        saveActiveReaderState()
        guard tabStore.closeTab(id) else { return }
        saveCurrentSession()

        if !tabStore.hasOpenDocuments {
            isOutlineVisible = false
        }

        if previousSelectedTabID == id || selectedTabID != previousSelectedTabID {
            prepareForSelectedReaderChange()
        }
    }

    func restoreClosedDocumentTab() {
        saveActiveReaderState()

        guard tabStore.restoreClosedDocumentTab() else { return }
        saveCurrentSession()
        prepareForSelectedReaderChange()
    }

    public func selectNextTab() {
        saveActiveReaderState()
        guard tabStore.selectNextTab() else { return }
        saveCurrentSession()
        prepareForSelectedReaderChange()
    }

    public func selectPreviousTab() {
        saveActiveReaderState()
        guard tabStore.selectPreviousTab() else { return }
        saveCurrentSession()
        prepareForSelectedReaderChange()
    }

    func restorePreviousTabsIfNeeded() {
        guard !didRestorePreviousTabs,
              !hasOpenDocuments,
              AppPreferences.restoresPreviousTabs(),
              let session = AppSessionPersistence.load() else {
            didRestorePreviousTabs = true
            return
        }

        didRestorePreviousTabs = true
        let tabs = session.tabs.compactMap { persistedTab -> DocumentTab? in
            let url = URL(fileURLWithPath: persistedTab.path)
            guard var tab = documentCoordinator.openTab(for: url) else { return nil }
            tab.snapshot = persistedTab.snapshot ?? .initial
            return tab
        }

        guard tabStore.restoreSessionTabs(tabs, selectedURLPath: session.selectedURLPath) else { return }
        prepareForSelectedReaderChange()
    }

    public func saveCurrentSession() {
        AppSessionPersistence.save(tabs: tabs, selectedTabID: selectedTabID)
    }
}
