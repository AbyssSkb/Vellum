import Foundation

struct TabStore {
    private(set) var tabs: [PDFTab] = []
    private(set) var selectedTabID: PDFTab.ID?

    private var closedPDFTabHistory = ClosedPDFTabHistory()

    var hasOpenTabs: Bool {
        !tabs.isEmpty
    }

    var selectedTab: PDFTab? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    var selectedIndex: Int? {
        guard let selectedTabID else { return nil }
        return tabs.firstIndex { $0.id == selectedTabID }
    }

    func tab(for url: URL) -> PDFTab? {
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        return tabs.first { $0.url?.standardizedFileURL.resolvingSymlinksInPath() == canonicalURL }
    }

    mutating func selectTab(_ id: PDFTab.ID) -> Bool {
        guard selectedTabID != id, tabs.contains(where: { $0.id == id }) else { return false }
        selectedTabID = id
        return true
    }

    mutating func openInCurrentTab(_ tab: PDFTab) {
        if let url = tab.url, let existingTab = self.tab(for: url) {
            selectedTabID = existingTab.id
            return
        }

        if let index = selectedIndex {
            tabs[index] = tab
        } else {
            tabs = [tab]
        }
        selectedTabID = tab.id
    }

    mutating func openInNewTabs(_ newTabs: [PDFTab]) -> Bool {
        guard !newTabs.isEmpty else { return false }
        for tab in newTabs {
            if let url = tab.url, let existingTab = self.tab(for: url) {
                selectedTabID = existingTab.id
            } else {
                tabs.append(tab)
                selectedTabID = tab.id
            }
        }
        return true
    }

    mutating func restoreSessionTabs(_ restoredTabs: [PDFTab], selectedURLPath: String?) -> Bool {
        guard !restoredTabs.isEmpty else { return false }
        tabs = []
        _ = openInNewTabs(restoredTabs)

        if let selectedURLPath,
           let selectedTab = tab(for: URL(fileURLWithPath: selectedURLPath)) {
            selectedTabID = selectedTab.id
        } else {
            selectedTabID = tabs.first?.id
        }

        return true
    }

    mutating func closeSelectedTab() -> Bool {
        guard let selectedTabID else { return false }
        return closeTab(selectedTabID)
    }

    mutating func closeTab(_ id: PDFTab.ID) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }

        let closedSelectedTab = tabs[index].id == selectedTabID
        closedPDFTabHistory.remember(tabs[index])
        tabs.remove(at: index)

        if tabs.isEmpty {
            self.selectedTabID = nil
        } else if closedSelectedTab {
            self.selectedTabID = tabs[min(index, tabs.count - 1)].id
        }

        return true
    }

    mutating func restoreClosedPDFTab(loader: (URL) -> PDFTab?) -> Bool {
        guard let closedTab = closedPDFTabHistory.restore() else { return false }
        if let existingTab = tab(for: closedTab.url) {
            selectedTabID = existingTab.id
            return true
        }
        guard var tab = loader(closedTab.url) else { return false }
        tab.snapshot = closedTab.snapshot ?? .initial
        tabs.append(tab)
        selectedTabID = tab.id
        return true
    }

    mutating func selectNextTab() -> Bool {
        guard let index = selectedIndex, !tabs.isEmpty else { return false }
        selectedTabID = tabs[(index + 1) % tabs.count].id
        return true
    }

    mutating func selectPreviousTab() -> Bool {
        guard let index = selectedIndex, !tabs.isEmpty else { return false }
        selectedTabID = tabs[(index - 1 + tabs.count) % tabs.count].id
        return true
    }

    mutating func saveSnapshot(_ snapshot: ReaderSnapshot, for tabID: PDFTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].snapshot = snapshot
    }

    func snapshotForSelectedTab() -> ReaderSnapshot? {
        selectedTab?.snapshot
    }
}
