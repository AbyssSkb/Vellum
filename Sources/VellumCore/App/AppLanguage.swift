import Foundation
import SwiftUI

public enum AppUILanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case chinese = "zh-Hans"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english:
            return "English"
        case .chinese:
            return "中文"
        }
    }

    public var systemImage: String {
        switch self {
        case .english:
            return "textformat.abc"
        case .chinese:
            return "character.book.closed"
        }
    }

    public static func saved(in defaults: UserDefaults = .standard) -> AppUILanguage {
        if let rawValue = defaults.string(forKey: AppPreferenceKeys.appLanguage),
           let language = AppUILanguage(rawValue: rawValue) {
            return language
        }
        return systemDefault()
    }

    public static func saved(rawValue: String) -> AppUILanguage {
        AppUILanguage(rawValue: rawValue) ?? systemDefault()
    }

    public static func systemDefault(preferredLanguages: [String] = Locale.preferredLanguages) -> AppUILanguage {
        let firstLanguage = preferredLanguages.first?.lowercased() ?? ""
        return firstLanguage.hasPrefix("zh") ? .chinese : .english
    }

    public func text(_ key: AppText) -> String {
        key.localized(in: self)
    }
}

public enum AppText {
    case ai
    case aiExplanation
    case aiHeaderSubtitle
    case apiKey
    case appLanguage
    case appLanguageSubtitle
    case appUI
    case askingTarget(String)
    case automaticallyCheck
    case automaticallyCheckSubtitle
    case baseURL
    case cancel
    case checkNow
    case checkForUpdatesMenu
    case checkingCodex
    case checkingEndpoint
    case chooseFile
    case closeTab
    case closeTabNamed(String)
    case codex
    case command
    case connectedNoModels
    case contents
    case currentModel
    case currentTab
    case currentVersion
    case defaultHighlight
    case defaultHighlightSubtitle
    case defaultOpenMode
    case defaultOpenModeSubtitle
    case defaultStatus
    case diagnosticsModels
    case diagnosticsRequest
    case doubleClickTranslate
    case doubleClickTranslateSubtitle
    case downloadAndInstall
    case downloadedBytes(String)
    case downloadingVersion(String)
    case endpoint
    case executable
    case fetchModels
    case fetching
    case fetchingModels
    case fetchingModelsFrom(String)
    case filesAndTabs
    case fitPage
    case fitWidth
    case general
    case generalHeaderSubtitle
    case highlightsAndAI
    case installingVersion(String)
    case installingDetail
    case jumpBackwardForward
    case language
    case later
    case loading
    case loadingModels
    case model
    case modelOverride
    case modelsLoaded(Int)
    case modelOverrideHint
    case modelChoicesHint
    case navigate
    case newTabs
    case nextTab
    case noContents
    case noDocument
    case noMatchingTabs
    case notChecked
    case notSet
    case openFileZoom
    case openFileZoomSubtitle
    case openGitHub
    case openDiskImage
    case openMenu
    case openPDF
    case openReleases
    case pageOverview
    case preparingDownload
    case previousTab
    case profile
    case prompt
    case provider
    case promptReset
    case promptTargetLanguage
    case promptTemplate
    case promptVariables
    case promptVariablesHint
    case reading
    case releaseNotesFallback
    case restorePreviousTabs
    case restorePreviousTabsSubtitle
    case search
    case searchNoMatch
    case searchOpenTabs
    case searchTypeHint
    case selected
    case selectHighlightColorHint
    case settings
    case settingsMenu
    case shortcuts
    case shortcutsHeaderSubtitle
    case startup
    case testCodex
    case testEndpoint
    case testModel
    case testing
    case textSelection
    case toggleContents
    case toggleContentsSidebar
    case toggleContentsHint
    case uiLanguage
    case untitled
    case unableToCheckUpdates
    case unableToCheckUpdatesDetail
    case unableToDownloadUpdate
    case unableToDownloadUpdateDetail(String)
    case unableToInstallUpdate
    case unableToInstallUpdateDetail(String)
    case updateAvailableTitle(String)
    case updateAvailableInstallDetail(current: String)
    case updateAvailableGitHubDetail(current: String)
    case updateWindowTitle
    case updates
    case useCodexDefault
    case useDefaultProfile
    case upToDate
    case upToDateDetail(current: String, latest: String)
    case validation
    case view
    case whatsNew
    case yellowHighlight
    case greenHighlight
    case cyanHighlight
    case purpleHighlight
    case pinkHighlight
}

public extension AppText {
    func localized(in language: AppUILanguage) -> String {
        switch language {
        case .english:
            return english
        case .chinese:
            return chinese
        }
    }

    private var english: String {
        switch self {
        case .ai: return "AI"
        case .aiExplanation: return "AI Explanation"
        case .aiHeaderSubtitle: return "Choose a provider, enter its key, then pick the model Vellum should use."
        case .apiKey: return "API Key"
        case .appLanguage: return "App Language"
        case .appLanguageSubtitle: return "Choose the language used by Vellum's interface."
        case .appUI: return "App UI"
        case .askingTarget(let target): return "Asking \(target)..."
        case .automaticallyCheck: return "Automatically Check"
        case .automaticallyCheckSubtitle: return "Look for new releases shortly after launch."
        case .baseURL: return "Base URL"
        case .cancel: return "Cancel"
        case .checkNow: return "Check Now"
        case .checkForUpdatesMenu: return "Check for Updates..."
        case .checkingCodex: return "Checking Codex..."
        case .checkingEndpoint: return "Checking endpoint..."
        case .chooseFile: return "Choose File"
        case .closeTab: return "Close Tab"
        case .closeTabNamed(let title): return "Close \(title)"
        case .codex: return "Codex"
        case .command: return "Command"
        case .connectedNoModels: return "Connected. No models returned."
        case .contents: return "Contents"
        case .currentModel: return "Current Model"
        case .currentTab: return "Current Tab"
        case .currentVersion: return "Current Version"
        case .defaultHighlight: return "Default Highlight"
        case .defaultHighlightSubtitle: return "Pick the highlight color used by new markings."
        case .defaultOpenMode: return "Default Open Mode"
        case .defaultOpenModeSubtitle: return "Choose where the Open command places PDFs."
        case .defaultStatus: return "Default"
        case .diagnosticsModels: return "Models"
        case .diagnosticsRequest: return "Request"
        case .doubleClickTranslate: return "Double-Click Translate"
        case .doubleClickTranslateSubtitle: return "Translate the selected word after a text double-click."
        case .downloadAndInstall: return "Download and Install"
        case .downloadedBytes(let bytes): return "\(bytes) downloaded"
        case .downloadingVersion(let version): return "Downloading Vellum \(version)"
        case .endpoint: return "Endpoint"
        case .executable: return "Executable"
        case .fetchModels: return "Fetch Models"
        case .fetching: return "Fetching"
        case .fetchingModels: return "Fetching models..."
        case .fetchingModelsFrom(let provider): return "Loading models from \(provider)..."
        case .filesAndTabs: return "Files and Tabs"
        case .fitPage: return "Fit Page"
        case .fitWidth: return "Fit Width"
        case .general: return "General"
        case .generalHeaderSubtitle: return "Set startup, reading, and update behavior."
        case .highlightsAndAI: return "Highlights and AI"
        case .installingVersion(let version): return "Installing Vellum \(version)"
        case .installingDetail: return "Vellum will quit, update itself, and reopen."
        case .jumpBackwardForward: return "Jump backward or forward"
        case .language: return "Language"
        case .later: return "Later"
        case .loading: return "Loading"
        case .loadingModels: return "Loading models"
        case .model: return "Model"
        case .modelOverride: return "Model Override"
        case .modelsLoaded(let count): return "\(count) models loaded."
        case .modelOverrideHint: return "Leave Model Override empty to use Codex default."
        case .modelChoicesHint: return "Fetched models will appear as choices for Current Model."
        case .navigate: return "Navigate"
        case .newTabs: return "New Tabs"
        case .nextTab: return "Next Tab"
        case .noContents: return "No contents"
        case .noDocument: return "No document"
        case .noMatchingTabs: return "No matching tabs"
        case .notChecked: return "Not checked"
        case .notSet: return "Not set"
        case .openFileZoom: return "Open File Zoom"
        case .openFileZoomSubtitle: return "Choose the initial zoom for newly opened PDFs."
        case .openGitHub: return "Open GitHub"
        case .openDiskImage: return "Open Disk Image"
        case .openMenu: return "Open..."
        case .openPDF: return "Open a PDF"
        case .openReleases: return "Open Releases"
        case .pageOverview: return "Page Overview"
        case .preparingDownload: return "Preparing download..."
        case .previousTab: return "Previous Tab"
        case .profile: return "Profile"
        case .prompt: return "Prompt"
        case .provider: return "Provider"
        case .promptReset: return "Reset Prompt"
        case .promptTargetLanguage: return "Target Output Language"
        case .promptTemplate: return "Template"
        case .promptVariables: return "Variables"
        case .promptVariablesHint: return "Use variables like {{selectedText}} and {{targetLanguage}}."
        case .reading: return "Reading"
        case .releaseNotesFallback: return "Release notes are still syncing. Open GitHub to view the full changelog."
        case .restorePreviousTabs: return "Restore Previous Tabs"
        case .restorePreviousTabsSubtitle: return "Reopen PDFs and reading positions from the last session."
        case .search: return "Search"
        case .searchNoMatch: return "no match"
        case .searchOpenTabs: return "Search open tabs"
        case .searchTypeHint: return "type"
        case .selected: return "Selected"
        case .selectHighlightColorHint: return "Select this highlight color"
        case .settings: return "Settings"
        case .settingsMenu: return "Settings..."
        case .shortcuts: return "Shortcuts"
        case .shortcutsHeaderSubtitle: return "Keyboard commands available in the reader."
        case .startup: return "Startup"
        case .testCodex: return "Test Codex"
        case .testEndpoint: return "Test Endpoint"
        case .testModel: return "Test Model"
        case .testing: return "Testing"
        case .textSelection: return "Text Selection"
        case .toggleContents: return "Toggle Contents"
        case .toggleContentsSidebar: return "Toggle Contents Sidebar"
        case .toggleContentsHint: return "Shows or hides the document outline"
        case .uiLanguage: return "UI Language"
        case .untitled: return "Untitled"
        case .unableToCheckUpdates: return "Unable to check for updates"
        case .unableToCheckUpdatesDetail: return "GitHub may be unreachable or rate-limited right now. You can open the releases page and try again later."
        case .unableToDownloadUpdate: return "Unable to download the update"
        case .unableToDownloadUpdateDetail(let error): return "\(error)\n\nOpen the release page to download it manually."
        case .unableToInstallUpdate: return "Unable to install the update"
        case .unableToInstallUpdateDetail(let error): return "\(error)\n\nThe installer was downloaded. Open the disk image and install it manually."
        case .updateAvailableTitle(let version): return "Vellum \(version) is available"
        case .updateAvailableInstallDetail(let current): return "You are currently using Vellum \(current). Download and install the latest version now."
        case .updateAvailableGitHubDetail(let current): return "You are currently using Vellum \(current). Open GitHub to download the latest version."
        case .updateWindowTitle: return "Vellum Update"
        case .updates: return "Updates"
        case .useCodexDefault: return "Use Codex default"
        case .useDefaultProfile: return "Use default profile"
        case .upToDate: return "Vellum is up to date"
        case .upToDateDetail(let current, let latest): return "You are using Vellum \(current). The latest release found is \(latest)."
        case .validation: return "Validation"
        case .view: return "View"
        case .whatsNew: return "What's new"
        case .yellowHighlight: return "Yellow highlight"
        case .greenHighlight: return "Green highlight"
        case .cyanHighlight: return "Cyan highlight"
        case .purpleHighlight: return "Purple highlight"
        case .pinkHighlight: return "Pink highlight"
        }
    }

    private var chinese: String {
        switch self {
        case .ai: return "AI"
        case .aiExplanation: return "AI 解释"
        case .aiHeaderSubtitle: return "选择服务商，填写密钥，然后选择 Vellum 使用的模型。"
        case .apiKey: return "API 密钥"
        case .appLanguage: return "应用语言"
        case .appLanguageSubtitle: return "选择 Vellum 界面使用的语言。"
        case .appUI: return "应用界面"
        case .askingTarget(let target): return "正在请求 \(target)..."
        case .automaticallyCheck: return "自动检查"
        case .automaticallyCheckSubtitle: return "启动后自动检查新版本。"
        case .baseURL: return "Base URL"
        case .cancel: return "取消"
        case .checkNow: return "立即检查"
        case .checkForUpdatesMenu: return "检查更新..."
        case .checkingCodex: return "正在检查 Codex..."
        case .checkingEndpoint: return "正在检查端点..."
        case .chooseFile: return "选择文件"
        case .closeTab: return "关闭标签页"
        case .closeTabNamed(let title): return "关闭 \(title)"
        case .codex: return "Codex"
        case .command: return "命令"
        case .connectedNoModels: return "已连接，但没有返回模型。"
        case .contents: return "目录"
        case .currentModel: return "当前模型"
        case .currentTab: return "当前标签页"
        case .currentVersion: return "当前版本"
        case .defaultHighlight: return "默认高亮"
        case .defaultHighlightSubtitle: return "选择新标注默认使用的高亮颜色。"
        case .defaultOpenMode: return "默认打开方式"
        case .defaultOpenModeSubtitle: return "选择打开命令把 PDF 放到哪里。"
        case .defaultStatus: return "默认"
        case .diagnosticsModels: return "模型"
        case .diagnosticsRequest: return "请求"
        case .doubleClickTranslate: return "双击翻译"
        case .doubleClickTranslateSubtitle: return "双击选中单词后自动翻译。"
        case .downloadAndInstall: return "下载并安装"
        case .downloadedBytes(let bytes): return "已下载 \(bytes)"
        case .downloadingVersion(let version): return "正在下载 Vellum \(version)"
        case .endpoint: return "端点"
        case .executable: return "可执行文件"
        case .fetchModels: return "获取模型"
        case .fetching: return "获取中"
        case .fetchingModels: return "正在获取模型..."
        case .fetchingModelsFrom(let provider): return "正在从 \(provider) 加载模型..."
        case .filesAndTabs: return "文件与标签页"
        case .fitPage: return "适合整页"
        case .fitWidth: return "适合宽度"
        case .general: return "通用"
        case .generalHeaderSubtitle: return "设置启动、阅读和更新行为。"
        case .highlightsAndAI: return "高亮与 AI"
        case .installingVersion(let version): return "正在安装 Vellum \(version)"
        case .installingDetail: return "Vellum 会退出、更新自己，然后重新打开。"
        case .jumpBackwardForward: return "向后或向前跳转"
        case .language: return "语言"
        case .later: return "稍后"
        case .loading: return "加载中"
        case .loadingModels: return "正在加载模型"
        case .model: return "模型"
        case .modelOverride: return "模型覆盖"
        case .modelsLoaded(let count): return "已加载 \(count) 个模型。"
        case .modelOverrideHint: return "留空则使用 Codex 默认模型。"
        case .modelChoicesHint: return "获取到的模型会作为当前模型的可选项显示。"
        case .navigate: return "导航"
        case .newTabs: return "新标签页"
        case .nextTab: return "下一个标签页"
        case .noContents: return "没有目录"
        case .noDocument: return "没有文档"
        case .noMatchingTabs: return "没有匹配的标签页"
        case .notChecked: return "未检查"
        case .notSet: return "未设置"
        case .openFileZoom: return "打开文件缩放"
        case .openFileZoomSubtitle: return "选择新打开 PDF 的初始缩放方式。"
        case .openGitHub: return "打开 GitHub"
        case .openDiskImage: return "打开磁盘镜像"
        case .openMenu: return "打开..."
        case .openPDF: return "打开 PDF"
        case .openReleases: return "打开发布页面"
        case .pageOverview: return "页面概览"
        case .preparingDownload: return "正在准备下载..."
        case .previousTab: return "上一个标签页"
        case .profile: return "Profile"
        case .prompt: return "提示词"
        case .provider: return "服务商"
        case .promptReset: return "重置提示词"
        case .promptTargetLanguage: return "目标输出语言"
        case .promptTemplate: return "模板"
        case .promptVariables: return "变量"
        case .promptVariablesHint: return "可以使用 {{selectedText}} 和 {{targetLanguage}} 这类变量。"
        case .reading: return "阅读"
        case .releaseNotesFallback: return "更新日志仍在同步。打开 GitHub 查看完整变更。"
        case .restorePreviousTabs: return "恢复上次标签页"
        case .restorePreviousTabsSubtitle: return "重新打开上次会话的 PDF 和阅读位置。"
        case .search: return "搜索"
        case .searchNoMatch: return "无匹配"
        case .searchOpenTabs: return "搜索已打开的标签页"
        case .searchTypeHint: return "输入"
        case .selected: return "已选"
        case .selectHighlightColorHint: return "选择这个高亮颜色"
        case .settings: return "设置"
        case .settingsMenu: return "设置..."
        case .shortcuts: return "快捷键"
        case .shortcutsHeaderSubtitle: return "阅读器中可用的键盘命令。"
        case .startup: return "启动"
        case .testCodex: return "测试 Codex"
        case .testEndpoint: return "测试端点"
        case .testModel: return "测试模型"
        case .testing: return "测试中"
        case .textSelection: return "文本选择"
        case .toggleContents: return "切换目录"
        case .toggleContentsSidebar: return "切换目录侧边栏"
        case .toggleContentsHint: return "显示或隐藏文档目录"
        case .uiLanguage: return "界面语言"
        case .untitled: return "未命名"
        case .unableToCheckUpdates: return "无法检查更新"
        case .unableToCheckUpdatesDetail: return "GitHub 现在可能无法访问或触发了限流。你可以打开发布页面稍后再试。"
        case .unableToDownloadUpdate: return "无法下载更新"
        case .unableToDownloadUpdateDetail(let error): return "\(error)\n\n请打开发布页面手动下载。"
        case .unableToInstallUpdate: return "无法安装更新"
        case .unableToInstallUpdateDetail(let error): return "\(error)\n\n安装器已下载。请打开磁盘镜像手动安装。"
        case .updateAvailableTitle(let version): return "Vellum \(version) 可用"
        case .updateAvailableInstallDetail(let current): return "你当前正在使用 Vellum \(current)。现在可以下载并安装最新版本。"
        case .updateAvailableGitHubDetail(let current): return "你当前正在使用 Vellum \(current)。请打开 GitHub 下载最新版本。"
        case .updateWindowTitle: return "Vellum 更新"
        case .updates: return "更新"
        case .useCodexDefault: return "使用 Codex 默认值"
        case .useDefaultProfile: return "使用默认 Profile"
        case .upToDate: return "Vellum 已是最新版本"
        case .upToDateDetail(let current, let latest): return "你正在使用 Vellum \(current)。检测到的最新版本是 \(latest)。"
        case .validation: return "验证"
        case .view: return "视图"
        case .whatsNew: return "更新内容"
        case .yellowHighlight: return "黄色高亮"
        case .greenHighlight: return "绿色高亮"
        case .cyanHighlight: return "青色高亮"
        case .purpleHighlight: return "紫色高亮"
        case .pinkHighlight: return "粉色高亮"
        }
    }
}

private struct AppUILanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppUILanguage.saved()
}

public extension EnvironmentValues {
    var appUILanguage: AppUILanguage {
        get { self[AppUILanguageEnvironmentKey.self] }
        set { self[AppUILanguageEnvironmentKey.self] = newValue }
    }
}
