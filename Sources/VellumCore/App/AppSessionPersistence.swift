import Foundation

struct PersistedAppSession: Codable, Equatable {
    var tabs: [PersistedDocumentTab]
    var selectedURLPath: String?
}

struct PersistedDocumentTab: Codable, Equatable {
    var path: String
    var snapshot: ReaderSnapshot?
    var kind: String?
}

enum AppSessionPersistence {
    private static let sessionKey = "VellumPreviousSession"

    static func save(tabs: [DocumentTab], selectedTabID: DocumentTab.ID?, defaults: UserDefaults = .standard) {
        let persistedTabs = tabs.compactMap { tab -> PersistedDocumentTab? in
            guard let url = tab.url?.standardizedFileURL else { return nil }
            let kind = DocumentCoordinator.isMarkdownURL(url) ? "markdown" : "pdf"
            return PersistedDocumentTab(path: url.path, snapshot: tab.snapshot, kind: kind)
        }

        guard !persistedTabs.isEmpty else {
            defaults.removeObject(forKey: sessionKey)
            return
        }

        let selectedURLPath = tabs.first { $0.id == selectedTabID }?.url?.standardizedFileURL.path
        let session = PersistedAppSession(tabs: persistedTabs, selectedURLPath: selectedURLPath)

        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: sessionKey)
        }
    }

    static func load(defaults: UserDefaults = .standard) -> PersistedAppSession? {
        guard let data = defaults.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(PersistedAppSession.self, from: data)
    }
}
