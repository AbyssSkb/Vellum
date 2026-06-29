import Foundation
import Testing
@testable import VellumCore

@Suite("App preferences")
struct AppPreferenceTests {
    @Test
    func defaultOpenModeFallsBackToCurrentTab() {
        let defaults = isolatedDefaults()

        #expect(DefaultOpenModePreference.saved(in: defaults) == .currentTab)

        defaults.set(DefaultOpenModePreference.newTabs.rawValue, forKey: AppPreferenceKeys.defaultOpenMode)
        #expect(DefaultOpenModePreference.saved(in: defaults) == .newTabs)
    }

    @Test
    func booleanPreferencesUseExpectedDefaults() {
        let defaults = isolatedDefaults()

        #expect(AppPreferences.automaticallyChecksForUpdates(in: defaults))
        #expect(AppPreferences.doubleClickTranslatesSelection(in: defaults))
        #expect(!AppPreferences.restoresPreviousTabs(in: defaults))
    }

    @Test
    func sessionPersistenceRoundTripsTabsAndSnapshots() {
        let defaults = isolatedDefaults()
        let selectedID = UUID()
        let snapshot = ReaderSnapshot(
            pageIndex: 3,
            pointOnPage: .init(x: 10, y: 20),
            scrollOrigin: .init(x: 4, y: 8),
            scaleFactor: 1.25,
            autoScales: false
        )
        let selectedTab = PDFTab(
            id: selectedID,
            url: URL(fileURLWithPath: "/tmp/selected.pdf"),
            document: nil,
            snapshot: snapshot
        )
        let otherTab = PDFTab(
            url: URL(fileURLWithPath: "/tmp/other.pdf"),
            document: nil
        )

        AppSessionPersistence.save(tabs: [otherTab, selectedTab], selectedTabID: selectedID, defaults: defaults)

        let session = AppSessionPersistence.load(defaults: defaults)
        #expect(session?.tabs.map(\.path) == ["/tmp/other.pdf", "/tmp/selected.pdf"])
        #expect(session?.selectedURLPath == "/tmp/selected.pdf")
        #expect(session?.tabs.last?.snapshot == snapshot)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "VellumTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
