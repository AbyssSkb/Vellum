import Foundation
import Testing
@testable import VellumCore

@Suite("App preferences")
struct AppPreferenceTests {
    @Test
    func defaultPDFOpenModeFallsBackToCurrentTab() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults

        #expect(DefaultPDFOpenModePreference.saved(in: defaults) == .currentTab)
        #expect(AppPreferences.defaultPDFOpenMode(in: defaults) == .currentTab)

        defaults.set(DefaultPDFOpenModePreference.newTabs.rawValue, forKey: AppPreferenceKeys.defaultPDFOpenMode)
        #expect(DefaultPDFOpenModePreference.saved(in: defaults) == .newTabs)
        #expect(AppPreferences.defaultPDFOpenMode(in: defaults) == .newTabs)
    }

    @Test
    func openFileZoomBehaviorFallsBackToFitWidth() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults

        #expect(AppPreferences.openFileZoomBehavior(in: defaults) == .fitWidth)

        defaults.set(OpenFileZoomPreference.fitPage.rawValue, forKey: AppPreferenceKeys.openFileZoomBehavior)
        #expect(AppPreferences.openFileZoomBehavior(in: defaults) == .fitPage)

        defaults.set("actualSize", forKey: AppPreferenceKeys.openFileZoomBehavior)
        #expect(AppPreferences.openFileZoomBehavior(in: defaults) == .fitWidth)
    }

    @Test
    func aiPronunciationAccentFallsBackToAmerican() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults

        #expect(AppPreferences.aiExplanationAutoPronunciationAccent(in: defaults) == .american)
        #expect(AIPronunciationAccentPreference.american.languageCode == "en-US")
        #expect(AIPronunciationAccentPreference.british.languageCode == "en-GB")

        defaults.set(AIPronunciationAccentPreference.british.rawValue, forKey: AppPreferenceKeys.aiExplanationAutoPronunciationAccent)
        #expect(AppPreferences.aiExplanationAutoPronunciationAccent(in: defaults) == .british)

        defaults.set("australian", forKey: AppPreferenceKeys.aiExplanationAutoPronunciationAccent)
        #expect(AppPreferences.aiExplanationAutoPronunciationAccent(in: defaults) == .american)
    }

    @Test
    func booleanPreferencesUseExpectedDefaults() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults

        #expect(AppPreferences.automaticallyChecksForUpdates(in: defaults))
        #expect(AppPreferences.doubleClickTranslatesSelection(in: defaults))
        #expect(!AppPreferences.automaticallyPronouncesAIExplanation(in: defaults))
        #expect(!AppPreferences.restoresPreviousTabs(in: defaults))
    }

    @Test
    func doubleClickActionPreservesExplicitLegacyPreference() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults

        #expect(AppPreferences.doubleClickAction(in: defaults) == .dictionary)
        defaults.set(true, forKey: AppPreferenceKeys.doubleClickTranslatesSelection)
        #expect(AppPreferences.doubleClickAction(in: defaults) == .ai)
        defaults.set(false, forKey: AppPreferenceKeys.doubleClickTranslatesSelection)
        #expect(AppPreferences.doubleClickAction(in: defaults) == .none)

        defaults.set(DoubleClickActionPreference.dictionary.rawValue, forKey: AppPreferenceKeys.doubleClickAction)
        #expect(AppPreferences.doubleClickAction(in: defaults) == .dictionary)
        defaults.set("invalid", forKey: AppPreferenceKeys.doubleClickAction)
        #expect(AppPreferences.doubleClickAction(in: defaults) == .none)
        defaults.removeObject(forKey: AppPreferenceKeys.doubleClickTranslatesSelection)
        #expect(AppPreferences.doubleClickAction(in: defaults) == .dictionary)
    }

    @Test
    func dictionaryDefaultsToAutomaticAmericanPronunciation() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults

        #expect(AppPreferences.automaticallyPronouncesDictionary(in: defaults))
        #expect(AppPreferences.dictionaryPronunciationAccent(in: defaults) == .american)
        defaults.set(false, forKey: AppPreferenceKeys.dictionaryAutoPronunciationEnabled)
        defaults.set(AIPronunciationAccentPreference.british.rawValue, forKey: AppPreferenceKeys.dictionaryPronunciationAccent)
        #expect(!AppPreferences.automaticallyPronouncesDictionary(in: defaults))
        #expect(AppPreferences.dictionaryPronunciationAccent(in: defaults) == .british)
        defaults.set("invalid", forKey: AppPreferenceKeys.dictionaryPronunciationAccent)
        #expect(AppPreferences.dictionaryPronunciationAccent(in: defaults) == .american)
    }

    @Test
    func dictionaryLocationRequiresExplicitSelection() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults
        let home = FileManager.default.homeDirectoryForCurrentUser

        #expect(AppPreferences.dictionaryLocation(in: defaults) == nil)
        defaults.set("~/Dictionaries/example.mdx", forKey: AppPreferenceKeys.dictionaryPath)
        #expect(AppPreferences.dictionaryLocation(in: defaults)?.path == home.appendingPathComponent("Dictionaries/example.mdx").path)
        defaults.set("/tmp/dictionary/example.mdx", forKey: AppPreferenceKeys.dictionaryPath)
        #expect(AppPreferences.dictionaryLocation(in: defaults)?.path == "/tmp/dictionary/example.mdx")
        defaults.set("", forKey: AppPreferenceKeys.dictionaryPath)
        #expect(AppPreferences.dictionaryLocation(in: defaults) == nil)
    }

    @Test
    func appLanguageUsesSavedValueAndSystemFallback() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults

        #expect(AppUILanguage.systemDefault(preferredLanguages: ["zh-Hans-CN"]) == .chinese)
        #expect(AppUILanguage.systemDefault(preferredLanguages: ["en-US"]) == .english)

        defaults.set(AppUILanguage.chinese.rawValue, forKey: AppPreferenceKeys.appLanguage)
        #expect(AppPreferences.appLanguage(in: defaults) == .chinese)

        defaults.set("fr", forKey: AppPreferenceKeys.appLanguage)
        #expect(AppPreferences.appLanguage(in: defaults) == AppUILanguage.systemDefault())
    }

    @Test
    func appLanguageLocalizesCommonInterfaceText() {
        #expect(AppUILanguage.english.text(.settings) == "Settings")
        #expect(AppUILanguage.chinese.text(.settings) == "设置")
        #expect(DefaultPDFOpenModePreference.newTabs.title(language: .chinese) == "新标签页")
        #expect(OpenFileZoomPreference.fitWidth.title(language: .chinese) == "适合宽度")
        #expect(AIPronunciationAccentPreference.british.title(language: .chinese) == "英式")
        #expect(DoubleClickActionPreference.dictionary.title(language: .chinese) == "词典")
        #expect(DoubleClickActionPreference.none.title(language: .english) == "Off")
        #expect(AppUILanguage.english.text(.dictionaryNotFound("test")).contains("test"))
        #expect(AppUILanguage.chinese.text(.dictionaryNoSelection) == "请先选中要查询的单词。")
        #expect(AppUILanguage.chinese.text(.dictionaryNotAdded) == "尚未添加词典")
    }

    @Test
    func sessionPersistenceRoundTripsTabsAndSnapshots() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults
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

}
