import Foundation

public enum AppPreferenceKeys {
    public static let automaticallyCheckForUpdates = "VellumAutomaticallyCheckForUpdates"
    public static let defaultOpenMode = "VellumDefaultOpenMode"
    public static let defaultHighlightColor = "VellumDefaultHighlightColor"
    public static let doubleClickTranslatesSelection = "VellumDoubleClickTranslatesSelection"
    public static let restorePreviousTabs = "VellumRestorePreviousTabs"
}

public enum VellumAppNotification {
    public static let checkForUpdatesRequested = Notification.Name("VellumCheckForUpdatesRequested")
    public static let highlightColorPreferenceChanged = Notification.Name("VellumHighlightColorPreferenceChanged")
}

public enum DefaultOpenModePreference: String, CaseIterable, Identifiable {
    case currentTab
    case newTabs

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .currentTab:
            return "Current Tab"
        case .newTabs:
            return "New Tabs"
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
        guard let rawValue = defaults.string(forKey: AppPreferenceKeys.defaultOpenMode),
              let mode = Self(rawValue: rawValue) else {
            return .currentTab
        }
        return mode
    }

    public var pdfOpenMode: PDFOpenMode {
        switch self {
        case .currentTab:
            return .currentTab
        case .newTabs:
            return .newTabs
        }
    }
}

public enum AppPreferences {
    public static func automaticallyChecksForUpdates(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: AppPreferenceKeys.automaticallyCheckForUpdates) as? Bool ?? true
    }

    public static func doubleClickTranslatesSelection(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: AppPreferenceKeys.doubleClickTranslatesSelection) as? Bool ?? true
    }

    public static func restoresPreviousTabs(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: AppPreferenceKeys.restorePreviousTabs) as? Bool ?? false
    }
}
