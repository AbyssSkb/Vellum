import Foundation

struct TabStore {
    private(set) var tabs: [DocumentTab] = []
    private(set) var selectedTabID: DocumentTab.ID?

    private var closedDocumentTabHistory = ClosedDocumentTabHistory()

    var hasOpenDocuments: Bool {
        !tabs.isEmpty
    }

    var selectedTab: DocumentTab? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    var selectedIndex: Int? {
        guard let selectedTabID else { return nil }
        return tabs.firstIndex { $0.id == selectedTabID }
    }

    mutating func selectTab(_ id: DocumentTab.ID) -> Bool {
        guard selectedTabID != id, tabs.contains(where: { $0.id == id }) else { return false }
        selectedTabID = id
        return true
    }

    mutating func openInCurrentTab(_ tab: DocumentTab) {
        if let index = selectedIndex {
            tabs[index] = tab
        } else {
            tabs = [tab]
        }
        selectedTabID = tab.id
    }

    mutating func openInNewTabs(_ newTabs: [DocumentTab]) -> Bool {
        guard !newTabs.isEmpty else { return false }
        tabs.append(contentsOf: newTabs)
        selectedTabID = newTabs.last?.id
        return true
    }

    mutating func restoreSessionTabs(_ restoredTabs: [DocumentTab], selectedURLPath: String?) -> Bool {
        guard !restoredTabs.isEmpty else { return false }
        tabs = restoredTabs

        if let selectedURLPath,
           let selectedTab = restoredTabs.first(where: { $0.url?.standardizedFileURL.path == selectedURLPath }) {
            selectedTabID = selectedTab.id
        } else {
            selectedTabID = restoredTabs.first?.id
        }

        return true
    }

    mutating func closeSelectedTab() -> Bool {
        guard let selectedTabID else { return false }
        return closeTab(selectedTabID)
    }

    mutating func closeTab(_ id: DocumentTab.ID) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }

        let closedSelectedTab = tabs[index].id == selectedTabID
        closedDocumentTabHistory.remember(tabs[index])
        tabs.remove(at: index)

        if tabs.isEmpty {
            self.selectedTabID = nil
        } else if closedSelectedTab {
            self.selectedTabID = tabs[min(index, tabs.count - 1)].id
        }

        return true
    }

    mutating func restoreClosedDocumentTab() -> Bool {
        guard let tab = closedDocumentTabHistory.restore() else { return false }
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

    mutating func saveSnapshot(_ snapshot: ReaderSnapshot, for tabID: DocumentTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].snapshot = snapshot
    }

    func snapshotForSelectedTab() -> ReaderSnapshot? {
        selectedTab?.snapshot
    }
}
