import Foundation

struct PersistedAppSession: Codable, Equatable {
    var tabs: [PersistedPDFTab]
    var selectedURLPath: String?
}

struct PersistedPDFTab: Codable, Equatable {
    var path: String
    var snapshot: ReaderSnapshot?
}

enum AppSessionPersistence {
    private static let sessionKey = "VellumPreviousSession"

    static func save(
        tabs: [PDFTab],
        selectedTabID: PDFTab.ID?,
        unresolvedSession: PersistedAppSession? = nil,
        defaults: UserDefaults = .standard
    ) {
        let openTabs = tabs.compactMap { tab -> PersistedPDFTab? in
            guard let url = tab.url?.standardizedFileURL else { return nil }
            return PersistedPDFTab(path: url.path, snapshot: tab.snapshot)
        }
        var seen = Set<URL>()
        let persistedTabs = (openTabs + (unresolvedSession?.tabs ?? [])).filter { tab in
            seen.insert(URL(fileURLWithPath: tab.path).standardizedFileURL.resolvingSymlinksInPath()).inserted
        }

        guard !persistedTabs.isEmpty else {
            defaults.removeObject(forKey: sessionKey)
            return
        }

        let selectedURLPath = tabs.first { $0.id == selectedTabID }?.url?.standardizedFileURL.path
            ?? unresolvedSession?.selectedURLPath
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
