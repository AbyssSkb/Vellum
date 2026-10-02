import Foundation

extension AppState {
    func selectTab(_ id: PDFTab.ID) {
        guard selectedTabID != id else { return }
        saveActiveReaderState()
        guard tabStore.selectTab(id) else { return }
        saveCurrentSession()
        prepareForSelectedReaderChange()
    }

    func selectTabFromSwitcher(_ id: PDFTab.ID) {
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
        if let existingTab = tabStore.tab(for: url) {
            selectTab(existingTab.id)
            return
        }
        saveActiveReaderState()

        guard let tab = pdfCoordinator.openTab(for: url) else { return }
        if let selectedTabID, !canCloseTab(selectedTabID) { return }

        tabStore.openInCurrentTab(tab)
        saveCurrentSession()
        prepareForSelectedReaderChange()
    }

    func openInNewTabs(urls: [URL]) {
        let previousSelectedTabID = selectedTabID
        saveActiveReaderState()

        var didOpenTab = false
        for url in urls {
            if let existingTab = tabStore.tab(for: url) {
                _ = tabStore.selectTab(existingTab.id)
                didOpenTab = true
            } else if let tab = pdfCoordinator.openTab(for: url) {
                _ = tabStore.openInNewTabs([tab])
                didOpenTab = true
            }
        }

        guard didOpenTab else { return }
        saveCurrentSession()
        if selectedTabID != previousSelectedTabID {
            prepareForSelectedReaderChange()
        }
    }

    public func closeSelectedTab() {
        guard let selectedTabID else { return }
        closeTab(selectedTabID)
    }

    func closeTab(_ id: PDFTab.ID) {
        guard canCloseTab(id) else { return }
        let previousSelectedTabID = selectedTabID
        saveActiveReaderState()
        guard tabStore.closeTab(id) else { return }
        saveCurrentSession()

        if !tabStore.hasOpenTabs {
            isOutlineVisible = false
        }

        if previousSelectedTabID == id || selectedTabID != previousSelectedTabID {
            prepareForSelectedReaderChange()
        }
    }

    func restoreClosedPDFTab() {
        let previousSelectedTabID = selectedTabID
        saveActiveReaderState()

        guard tabStore.restoreClosedPDFTab(loader: pdfCoordinator.openTab(for:)) else { return }
        saveCurrentSession()
        if selectedTabID != previousSelectedTabID {
            prepareForSelectedReaderChange()
        }
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
              !hasOpenTabs,
              AppPreferences.restoresPreviousTabs(in: sessionDefaults),
              let session = AppSessionPersistence.load(defaults: sessionDefaults) else {
            didRestorePreviousTabs = true
            return
        }

        didRestorePreviousTabs = true
        var openedURLs = Set<URL>()
        var unreadableTabs: [PersistedPDFTab] = []
        let tabs = session.tabs.compactMap { persistedTab -> PDFTab? in
            let url = URL(fileURLWithPath: persistedTab.path)
            guard openedURLs.insert(url.standardizedFileURL.resolvingSymlinksInPath()).inserted else { return nil }
            guard var tab = pdfCoordinator.openTab(for: url) else {
                unreadableTabs.append(persistedTab)
                return nil
            }
            tab.snapshot = persistedTab.snapshot ?? .initial
            return tab
        }
        unresolvedSession = PersistedAppSession(tabs: unreadableTabs, selectedURLPath: session.selectedURLPath)

        guard tabStore.restoreSessionTabs(tabs, selectedURLPath: session.selectedURLPath) else { return }
        prepareForSelectedReaderChange()
    }

    public func saveCurrentSession() {
        let openURLs = Set(tabs.compactMap { $0.url?.standardizedFileURL.resolvingSymlinksInPath() })
        unresolvedSession?.tabs.removeAll {
            openURLs.contains(URL(fileURLWithPath: $0.path).standardizedFileURL.resolvingSymlinksInPath())
        }
        AppSessionPersistence.save(
            tabs: tabs,
            selectedTabID: selectedTabID,
            unresolvedSession: unresolvedSession,
            defaults: sessionDefaults
        )
    }
}
