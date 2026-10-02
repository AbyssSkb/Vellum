@preconcurrency import AppKit
import Testing
@testable import VellumCore

@MainActor
@Suite("App state session")
struct AppStateSessionTests {
    @Test
    func failedRestoreEntriesKeepSnapshotsAndSelectionAfterEmptySave() throws {
        let first = URL(fileURLWithPath: "/tmp/vellum-session-first.pdf")
        let second = URL(fileURLWithPath: "/tmp/vellum-session-second.pdf")
        let session = PersistedAppSession(tabs: [
            PersistedPDFTab(path: first.path, snapshot: snapshot(page: 4)),
            PersistedPDFTab(path: second.path, snapshot: snapshot(page: 9))
        ], selectedURLPath: second.path)
        let (defaults, suiteName) = try sessionDefaults(session)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let loader = SessionPDFTabLoader()
        let state = appState(defaults: defaults, loader: loader)

        state.restorePreviousTabsIfNeeded()
        state.saveCurrentSession()

        #expect(state.tabs.isEmpty)
        #expect(loader.requestedURLs == [first, second])
        #expect(AppSessionPersistence.load(defaults: defaults) == session)
    }

    @Test
    func failedRestoreEntrySurvivesSnapshotAndLastTabClose() throws {
        let readable = URL(fileURLWithPath: "/tmp/vellum-session-readable.pdf")
        let missing = URL(fileURLWithPath: "/tmp/vellum-session-missing.pdf")
        let missingTab = PersistedPDFTab(path: missing.path, snapshot: snapshot(page: 9))
        let session = PersistedAppSession(tabs: [
            PersistedPDFTab(path: readable.path, snapshot: snapshot(page: 4)),
            missingTab
        ], selectedURLPath: missing.path)
        let (defaults, suiteName) = try sessionDefaults(session)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = appState(defaults: defaults, loader: SessionPDFTabLoader(loadableURLs: [readable]))

        state.restorePreviousTabsIfNeeded()
        let restoredTab = try #require(state.selectedTab)
        #expect(restoredTab.snapshot == snapshot(page: 4))
        let updatedSnapshot = snapshot(page: 7)
        state.saveSnapshot(updatedSnapshot, for: restoredTab.id)

        #expect(AppSessionPersistence.load(defaults: defaults) == PersistedAppSession(tabs: [
            PersistedPDFTab(path: readable.path, snapshot: updatedSnapshot),
            missingTab
        ], selectedURLPath: readable.path))

        state.closeSelectedTab()

        #expect(state.tabs.isEmpty)
        #expect(AppSessionPersistence.load(defaults: defaults) == PersistedAppSession(
            tabs: [missingTab], selectedURLPath: missing.path
        ))
    }

    @Test
    func recoveredCanonicalFileDoesNotReturnAfterExplicitClose() throws {
        let recovered = URL(fileURLWithPath: "/tmp/vellum-session-recovered.pdf")
        let alias = URL(fileURLWithPath: "/tmp/subdirectory/../vellum-session-recovered.pdf")
        let missing = URL(fileURLWithPath: "/tmp/vellum-session-still-missing.pdf")
        let missingTab = PersistedPDFTab(path: missing.path, snapshot: snapshot(page: 9))
        let session = PersistedAppSession(tabs: [
            PersistedPDFTab(path: recovered.path, snapshot: snapshot(page: 4)),
            missingTab
        ], selectedURLPath: missing.path)
        let (defaults, suiteName) = try sessionDefaults(session)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let loader = SessionPDFTabLoader()
        let state = appState(defaults: defaults, loader: loader)

        state.restorePreviousTabsIfNeeded()
        loader.loadableURLs = [recovered]
        state.openInNewTabs(urls: [alias])
        #expect(state.tabs.count == 1)

        state.closeSelectedTab()

        #expect(state.tabs.isEmpty)
        #expect(AppSessionPersistence.load(defaults: defaults) == PersistedAppSession(
            tabs: [missingTab], selectedURLPath: missing.path
        ))
    }

    @Test
    func legacyCanonicalDuplicatesLoadOnceAndKeepFirstSnapshot() throws {
        let readable = URL(fileURLWithPath: "/tmp/vellum-session-readable.pdf")
        let duplicate = URL(fileURLWithPath: "/tmp/subdirectory/../vellum-session-readable.pdf")
        let missing = URL(fileURLWithPath: "/tmp/vellum-session-missing.pdf")
        let missingDuplicate = URL(fileURLWithPath: "/tmp/subdirectory/../vellum-session-missing.pdf")
        let session = PersistedAppSession(tabs: [
            PersistedPDFTab(path: readable.path, snapshot: snapshot(page: 4)),
            PersistedPDFTab(path: duplicate.path, snapshot: snapshot(page: 7)),
            PersistedPDFTab(path: missing.path, snapshot: snapshot(page: 9)),
            PersistedPDFTab(path: missingDuplicate.path, snapshot: nil)
        ], selectedURLPath: duplicate.path)
        let (defaults, suiteName) = try sessionDefaults(session)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let loader = SessionPDFTabLoader(loadableURLs: [readable])
        let state = appState(defaults: defaults, loader: loader)

        state.restorePreviousTabsIfNeeded()
        state.restorePreviousTabsIfNeeded()
        state.saveCurrentSession()

        #expect(loader.requestedURLs == [readable, missing])
        #expect(state.tabs.count == 1)
        #expect(state.selectedTab?.url == readable)
        #expect(state.selectedTab?.snapshot == snapshot(page: 4))
        #expect(AppSessionPersistence.load(defaults: defaults)?.tabs == [session.tabs[0], session.tabs[2]])
    }

    private func sessionDefaults(_ session: PersistedAppSession) throws -> (UserDefaults, String) {
        let suiteName = "Vellum.AppStateSessionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(true, forKey: AppPreferenceKeys.restorePreviousTabs)
        defaults.set(try JSONEncoder().encode(session), forKey: "VellumPreviousSession")
        return (defaults, suiteName)
    }

    private func appState(defaults: UserDefaults, loader: SessionPDFTabLoader) -> AppState {
        AppState(
            sessionDefaults: defaults,
            pdfCoordinator: PDFCoordinator(loader: loader),
            keyboardController: KeyboardController(
                installsKeyMonitor: false,
                installsOpenURLObserver: false,
                notificationCenter: NotificationCenter(),
                openURLRelay: OpenURLRelay()
            )
        )
    }

    private func snapshot(page: Int) -> ReaderSnapshot {
        ReaderSnapshot(
            pageIndex: page,
            pointOnPage: NSPoint(x: 12, y: 34),
            scrollOrigin: NSPoint(x: 2, y: 8),
            scaleFactor: 1.5,
            autoScales: false
        )
    }
}

private final class SessionPDFTabLoader: PDFTabLoading {
    var loadableURLs: [URL]
    private(set) var requestedURLs: [URL] = []

    init(loadableURLs: [URL] = []) {
        self.loadableURLs = loadableURLs
    }

    func tab(for url: URL) -> PDFTab? {
        requestedURLs.append(url)
        guard loadableURLs.contains(where: {
            $0.standardizedFileURL.resolvingSymlinksInPath() == url.standardizedFileURL.resolvingSymlinksInPath()
        }) else { return nil }
        return PDFTab(url: url, document: nil, snapshot: .initial)
    }
}
