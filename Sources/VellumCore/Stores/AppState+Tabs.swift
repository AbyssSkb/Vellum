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
        restoreFocusAfterSwitcher()
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
        if let existingTab = tabStore.tab(for: url) {
            var failures: [String] = []
            let didReload = reloadTabIfNeeded(existingTab, from: url, failures: &failures)
            let didSelect = tabStore.selectTab(existingTab.id)
            saveCurrentSession()
            if didReload || didSelect {
                prepareForSelectedReaderChange()
            }
            showFileFailures(failures)
            return
        }

        guard let tab = openTabRestoringSession(for: url) else {
            showFileFailures([AppUILanguage.saved().text(.fileOpenFailed(
                name: url.lastPathComponent, reason: fileFailureReason(for: url)
            ))])
            return
        }
        if let selectedTabID, !canCloseTab(selectedTabID) { return }

        tabStore.openInCurrentTab(tab)
        saveCurrentSession()
        prepareForSelectedReaderChange()
    }

    func openInNewTabs(urls: [URL]) {
        let previousSelectedTabID = selectedTabID
        saveActiveReaderState()

        var didOpenTab = false
        var didReloadSelectedTab = false
        var openedCount = 0
        var failures: [String] = []
        for url in urls {
            if let existingTab = tabStore.tab(for: url) {
                let previousFailureCount = failures.count
                if reloadTabIfNeeded(existingTab, from: url, failures: &failures), existingTab.id == previousSelectedTabID {
                    didReloadSelectedTab = true
                }
                _ = tabStore.selectTab(existingTab.id)
                didOpenTab = true
                if failures.count == previousFailureCount { openedCount += 1 }
            } else if let tab = openTabRestoringSession(for: url) {
                _ = tabStore.openInNewTabs([tab])
                didOpenTab = true
                openedCount += 1
            } else {
                failures.append(AppUILanguage.saved().text(.fileOpenFailed(
                    name: url.lastPathComponent, reason: fileFailureReason(for: url)
                )))
            }
        }

        if didOpenTab {
            saveCurrentSession()
            if selectedTabID != previousSelectedTabID || didReloadSelectedTab {
                prepareForSelectedReaderChange()
            }
        }
        showFileFailures(failures, summary: urls.count > 1
                         ? .fileBatchOpenFailed(opened: openedCount, failed: failures.count) : nil)
    }

    private func openTabRestoringSession(for url: URL) -> PDFTab? {
        guard var tab = pdfCoordinator.openTab(for: url) else { return nil }
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        guard var snapshot = unresolvedSession?.tabs.first(where: {
            URL(fileURLWithPath: $0.path).standardizedFileURL.resolvingSymlinksInPath() == canonicalURL
        })?.snapshot else { return tab }
        if let document = tab.document,
           document.pageCount > 0, snapshot.pageIndex >= document.pageCount {
            snapshot.pageIndex = document.pageCount - 1
            snapshot.scrollOrigin = nil
        }
        tab.snapshot = snapshot
        return tab
    }

    private func reloadTabIfNeeded(_ tab: PDFTab, from url: URL, failures: inout [String]) -> Bool {
        guard let document = tab.document,
              let persistence = PDFAnnotationPersistence.existing(for: document),
              persistence.hasFileChanged(at: url),
              canCloseTab(tab.id) else { return false }
        guard let reloadedDocument = pdfCoordinator.openTab(for: url)?.document else {
            failures.append(AppUILanguage.saved().text(.fileReloadFailed(
                name: url.lastPathComponent, reason: fileFailureReason(for: url)
            )))
            return false
        }
        tabStore.replaceDocument(for: tab.id, with: reloadedDocument)
        return true
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
        guard let url = tabStore.nextClosedPDFTabURL else {
            showNotification(AppUILanguage.saved().text(.noClosedTabs), kind: .warning)
            return
        }
        let previousSelectedTabID = selectedTabID
        saveActiveReaderState()

        guard tabStore.restoreClosedPDFTab(loader: pdfCoordinator.openTab(for:)) else {
            showFileFailures([AppUILanguage.saved().text(.fileRestoreFailed(
                name: url.lastPathComponent, reason: fileFailureReason(for: url)
            ))])
            return
        }
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
        var failures: [String] = []
        let tabs = session.tabs.compactMap { persistedTab -> PDFTab? in
            let url = URL(fileURLWithPath: persistedTab.path)
            guard openedURLs.insert(url.standardizedFileURL.resolvingSymlinksInPath()).inserted else { return nil }
            guard var tab = pdfCoordinator.openTab(for: url) else {
                unreadableTabs.append(persistedTab)
                failures.append(AppUILanguage.saved().text(.fileRestoreFailed(
                    name: url.lastPathComponent, reason: fileFailureReason(for: url)
                )))
                return nil
            }
            tab.snapshot = persistedTab.snapshot ?? .initial
            return tab
        }
        unresolvedSession = PersistedAppSession(tabs: unreadableTabs, selectedURLPath: session.selectedURLPath)

        if tabStore.restoreSessionTabs(tabs, selectedURLPath: session.selectedURLPath) {
            prepareForSelectedReaderChange()
        }
        showFileFailures(failures, summary: .fileSessionRestoreFailed(restored: tabs.count, failed: failures.count))
    }

    private func fileFailureReason(for url: URL) -> String {
        AppUILanguage.saved().text(PDFDocumentLoader.failureReason(for: url))
    }

    private func showFileFailures(_ failures: [String], summary: AppText? = nil) {
        guard !failures.isEmpty else { return }
        let lines = summary.map { [AppUILanguage.saved().text($0)] } ?? []
        showNotification((lines + failures).joined(separator: "\n"), kind: .error)
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
