import Foundation

public enum AppPreferenceKeys {
    public static let appLanguage = "VellumAppLanguage"
    public static let automaticallyCheckForUpdates = "VellumAutomaticallyCheckForUpdates"
    public static let defaultPDFOpenMode = "VellumDefaultOpenMode"
    public static let defaultHighlightColor = "VellumDefaultHighlightColor"
    public static let doubleClickTranslatesSelection = "VellumDoubleClickTranslatesSelection"
    public static let aiExplanationAutoPronunciationEnabled = "VellumAIExplanationAutoPronunciationEnabled"
    public static let aiExplanationAutoPronunciationAccent = "VellumAIExplanationAutoPronunciationAccent"
    public static let restorePreviousTabs = "VellumRestorePreviousTabs"
    public static let openFileZoomBehavior = "VellumOpenFileZoomBehavior"
}

public enum VellumAppNotification {
    public static let checkForUpdatesRequested = Notification.Name("VellumCheckForUpdatesRequested")
    public static let highlightColorPreferenceChanged = Notification.Name("VellumHighlightColorPreferenceChanged")
}

public enum DefaultPDFOpenModePreference: String, CaseIterable, Identifiable {
    case currentTab
    case newTabs

    public var id: String { rawValue }

    public func title(language: AppUILanguage = AppUILanguage.saved()) -> String {
        switch self {
        case .currentTab:
            return language.text(.currentTab)
        case .newTabs:
            return language.text(.newTabs)
        }
    }

    public var systemImage: String {
        switch self {
        case .currentTab:
            return "rectangle"
        case .newTabs:
            return "rectangle.stack"
        }
    }

    public static func saved(in defaults: UserDefaults = .standard) -> Self {
        guard let rawValue = defaults.string(forKey: AppPreferenceKeys.defaultPDFOpenMode),
              let mode = Self(rawValue: rawValue) else {
            return .currentTab
        }
        return mode
    }

    public var openMode: PDFOpenMode {
        switch self {
        case .currentTab:
            return .currentTab
        case .newTabs:
            return .newTabs
        }
    }
}

public enum OpenFileZoomPreference: String, CaseIterable, Identifiable {
    case fitWidth
    case fitPage

    public var id: String { rawValue }

    public func title(language: AppUILanguage = AppUILanguage.saved()) -> String {
        switch self {
        case .fitWidth:
            return language.text(.fitWidth)
        case .fitPage:
            return language.text(.fitPage)
        }
    }

    public var systemImage: String {
        switch self {
        case .fitWidth:
            return "arrow.left.and.right"
        case .fitPage:
            return "rectangle.expand.vertical"
        }
    }

    public static func saved(in defaults: UserDefaults = .standard) -> Self {
        guard let rawValue = defaults.string(forKey: AppPreferenceKeys.openFileZoomBehavior),
              let behavior = Self(rawValue: rawValue) else {
            return .fitWidth
        }
        return behavior
    }
}

public enum AIPronunciationAccentPreference: String, CaseIterable, Identifiable {
    case american
    case british

    public var id: String { rawValue }

    public func title(language: AppUILanguage = AppUILanguage.saved()) -> String {
        switch self {
        case .american:
            return language.text(.americanEnglish)
        case .british:
            return language.text(.britishEnglish)
        }
    }

    public var systemImage: String {
        switch self {
        case .american:
            return "speaker.wave.2"
        case .british:
            return "speaker.wave.2.fill"
        }
    }

    public var languageCode: String {
        switch self {
        case .american:
            return "en-US"
        case .british:
            return "en-GB"
        }
    }

    public static func saved(in defaults: UserDefaults = .standard) -> Self {
        guard let rawValue = defaults.string(forKey: AppPreferenceKeys.aiExplanationAutoPronunciationAccent),
              let accent = Self(rawValue: rawValue) else {
            return .american
        }
        return accent
    }
}

public enum AppPreferences {
    public static func appLanguage(in defaults: UserDefaults = .standard) -> AppUILanguage {
        AppUILanguage.saved(in: defaults)
    }

    public static func automaticallyChecksForUpdates(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: AppPreferenceKeys.automaticallyCheckForUpdates) as? Bool ?? true
    }

    public static func doubleClickTranslatesSelection(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: AppPreferenceKeys.doubleClickTranslatesSelection) as? Bool ?? true
    }

    public static func automaticallyPronouncesAIExplanation(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: AppPreferenceKeys.aiExplanationAutoPronunciationEnabled) as? Bool ?? false
    }

    public static func aiExplanationAutoPronunciationAccent(in defaults: UserDefaults = .standard) -> AIPronunciationAccentPreference {
        AIPronunciationAccentPreference.saved(in: defaults)
    }

    public static func restoresPreviousTabs(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: AppPreferenceKeys.restorePreviousTabs) as? Bool ?? false
    }

    public static func defaultPDFOpenMode(in defaults: UserDefaults = .standard) -> PDFOpenMode {
        DefaultPDFOpenModePreference.saved(in: defaults).openMode
    }

    public static func openFileZoomBehavior(in defaults: UserDefaults = .standard) -> OpenFileZoomPreference {
        OpenFileZoomPreference.saved(in: defaults)
    }
}
