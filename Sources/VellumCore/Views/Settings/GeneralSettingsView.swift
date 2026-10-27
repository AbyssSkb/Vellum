@preconcurrency import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    let page: SettingsPage
    @Environment(\.appUILanguage) private var language
    @AppStorage(AppPreferenceKeys.appLanguage) private var appLanguage = AppUILanguage.systemDefault().rawValue
    @AppStorage(AppPreferenceKeys.defaultPDFOpenMode) private var defaultPDFOpenMode = DefaultPDFOpenModePreference.currentTab.rawValue
    @AppStorage(AppPreferenceKeys.defaultHighlightColor) private var defaultHighlightColor = HighlightColor.yellow.rawValue
    @AppStorage(AppPreferenceKeys.doubleClickAction) private var doubleClickAction = AppPreferences.doubleClickAction().rawValue
    @AppStorage(AppPreferenceKeys.dictionaryPath) private var dictionaryPath = ""
    @AppStorage(AppPreferenceKeys.dictionaryAutoPronunciationEnabled) private var dictionaryAutoPronunciation = true
    @AppStorage(AppPreferenceKeys.dictionaryPronunciationAccent) private var dictionaryPronunciationAccent = AIPronunciationAccentPreference.american.rawValue
    @AppStorage(AppPreferenceKeys.restorePreviousTabs) private var restorePreviousTabs = false
    @AppStorage(AppPreferenceKeys.openFileZoomBehavior) private var openFileZoomBehavior = OpenFileZoomPreference.fitWidth.rawValue
    @State private var logNotification: ToastMessage?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                switch page {
                case .general:
                    interfaceSection
                    startupSection
                    diagnosticsSection
                case .reading:
                    readingSection
                case .dictionary:
                    dictionarySection
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(VellumColors.backgroundColor)
        .background(SettingsScrollChromeConfigurator())
        .toast(logNotification)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: page.systemImage)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(VellumColors.mutedColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(page.title(language: language))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(VellumColors.foregroundColor)

                Text(headerSubtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(VellumColors.mutedColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.bottom, 4)
    }

    private var headerSubtitle: String {
        switch page {
        case .reading: return language.text(.readingHeaderSubtitle)
        case .dictionary: return language.text(.dictionaryHeaderSubtitle)
        default: return language.text(.generalHeaderSubtitle)
        }
    }

    private var interfaceSection: some View {
        GeneralSettingsPanel(title: language.text(.appUI), systemImage: "globe") {
            GeneralOptionRow(id: "app-language", title: language.text(.appLanguage), subtitle: language.text(.appLanguageSubtitle)) {
                LanguageSegmentedControl(selection: $appLanguage)
            }
        }
    }

    private var startupSection: some View {
        GeneralSettingsPanel(title: language.text(.startup), systemImage: "power") {
            VStack(spacing: 0) {
                GeneralToggleRow(
                    id: "restore-previous-tabs",
                    title: language.text(.restorePreviousTabs),
                    subtitle: language.text(.restorePreviousTabsSubtitle),
                    isOn: $restorePreviousTabs
                )
            }
        }
    }

    private var readingSection: some View {
        GeneralSettingsPanel(title: language.text(.reading), systemImage: "doc.text.magnifyingglass") {
            VStack(spacing: 0) {
                GeneralOptionRow(id: "default-open-mode", title: language.text(.defaultOpenMode), subtitle: language.text(.defaultOpenModeSubtitle)) {
                    GeneralSegmentedControl(
                        selection: $defaultPDFOpenMode,
                        options: DefaultPDFOpenModePreference.allCases,
                        language: language
                    )
                }
                GeneralOptionRow(id: "double-click-action", title: language.text(.doubleClickAction), subtitle: language.text(.doubleClickActionSubtitle)) {
                    HStack(spacing: 4) {
                        ForEach(DoubleClickActionPreference.allCases) { option in
                            GeneralSegmentButton(
                                id: option.rawValue,
                                title: option.title(language: language),
                                systemImage: option.systemImage,
                                isSelected: doubleClickAction == option.rawValue
                            ) {
                                doubleClickAction = option.rawValue
                            }
                        }
                    }
                    .padding(3)
                    .background(VellumColors.backgroundDeepColor.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                GeneralOptionRow(id: "open-file-zoom", title: language.text(.openFileZoom), subtitle: language.text(.openFileZoomSubtitle)) {
                    OpenFileZoomSegmentedControl(selection: $openFileZoomBehavior, language: language)
                }

                GeneralOptionRow(id: "default-highlight", title: language.text(.defaultHighlight), subtitle: language.text(.defaultHighlightSubtitle)) {
                    HighlightColorPicker(selection: $defaultHighlightColor, language: language)
                }
            }
        }
    }

    private var dictionarySection: some View {
        GeneralSettingsPanel(title: language.text(.localDictionary), systemImage: "character.book.closed") {
            VStack(spacing: 0) {
                GeneralOptionRow(
                    id: "dictionary-file",
                    title: language.text(.dictionaryFile),
                    subtitle: "\(dictionaryPath.isEmpty ? language.text(.dictionaryNotAdded) : (dictionaryPath as NSString).abbreviatingWithTildeInPath)\n\(language.text(.dictionaryFileSubtitle))"
                ) {
                    Button(action: chooseDictionaryFile) {
                        Label(language.text(.chooseFile), systemImage: "folder")
                    }
                    .buttonStyle(GeneralActionButtonStyle())
                    .settingsControl("choose-dictionary", action: chooseDictionaryFile)
                }

                GeneralToggleRow(
                    id: "dictionary-auto-pronunciation",
                    title: language.text(.dictionaryAutoPronunciation),
                    subtitle: language.text(.dictionaryAutoPronunciationSubtitle),
                    isOn: $dictionaryAutoPronunciation
                )

                GeneralOptionRow(
                    id: "dictionary-pronunciation-accent",
                    title: language.text(.dictionaryPronunciationAccent),
                    subtitle: language.text(.dictionaryPronunciationAccentSubtitle)
                ) {
                    HStack(spacing: 4) {
                        ForEach(AIPronunciationAccentPreference.allCases) { option in
                            GeneralSegmentButton(
                                id: option.rawValue,
                                title: option.title(language: language),
                                systemImage: option.systemImage,
                                isSelected: dictionaryPronunciationAccent == option.rawValue
                            ) {
                                dictionaryPronunciationAccent = option.rawValue
                            }
                        }
                    }
                    .padding(3)
                    .background(VellumColors.backgroundDeepColor.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
    }

    private func chooseDictionaryFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mdx") ?? .data]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = language.text(.dictionaryFile)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await DictionaryStore.shared.invalidate()
                DictionaryPopoverView.reusable = nil
                dictionaryPath = url.path
            }
        }
    }

    private var diagnosticsSection: some View {
        GeneralSettingsPanel(title: language.text(.diagnostics), systemImage: "waveform.path.ecg") {
            GeneralOptionRow(id: "ai-request-logs", title: language.text(.aiRequestLogs), subtitle: language.text(.aiRequestLogsSubtitle)) {
                HStack(spacing: 8) {
                    Button(action: openAIRequestLog) {
                        Label(language.text(.openLog), systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(GeneralActionButtonStyle())
                    .settingsControl("open-log", action: openAIRequestLog)

                    Button(action: clearAIRequestLog) {
                        Label(language.text(.clearLog), systemImage: "trash")
                    }
                    .buttonStyle(GeneralActionButtonStyle())
                    .settingsControl("clear-log", action: clearAIRequestLog)
                }
            }
        }
    }

    private func openAIRequestLog() {
        do {
            try AIRequestLogger.openLog()
            logNotification = ToastMessage(language.text(.aiLogsOpened), kind: .success)
        } catch {
            logNotification = ToastMessage(language.text(.aiLogsFailed(error.localizedDescription)), kind: .error)
        }
    }

    private func clearAIRequestLog() {
        do {
            try AIRequestLogger.clearLog()
            logNotification = ToastMessage(language.text(.aiLogsCleared), kind: .success)
        } catch {
            logNotification = ToastMessage(language.text(.aiLogsFailed(error.localizedDescription)), kind: .error)
        }
    }
}

struct GeneralSettingsPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(VellumColors.mutedColor)
                    .layoutPriority(1)

                VellumColors.borderColor.opacity(0.45)
                    .frame(height: 0.5)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GeneralToggleRow: View {
    let id: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(VellumColors.foregroundColor)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(VellumColors.mutedColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                TogglePill(isOn: isOn)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 58)
            .background(isHovered ? VellumColors.panelColor : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .settingsControl(id, action: { isOn.toggle() })
        .settingsRow(id)
        .onHover { isHovered = $0 }
    }
}

struct GeneralOptionRow<Content: View>: View {
    let id: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @State private var isCompact = false

    var body: some View {
        let layout = isCompact
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 18))
        layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VellumColors.foregroundColor)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(VellumColors.mutedColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            content
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 58)
        .onGeometryChange(for: Bool.self) { geometry in
            geometry.size.width < 540
        } action: { isCompact = $0 }
        .settingsRow(id)
    }
}

private struct GeneralSegmentedControl: View {
    @Binding var selection: String
    let options: [DefaultPDFOpenModePreference]
    let language: AppUILanguage

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                GeneralSegmentButton(
                    id: option.rawValue,
                    title: option.title(language: language),
                    systemImage: option.systemImage,
                    isSelected: selection == option.rawValue
                ) {
                    selection = option.rawValue
                }
            }
        }
        .padding(3)
        .background(VellumColors.backgroundDeepColor.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct OpenFileZoomSegmentedControl: View {
    @Binding var selection: String
    let language: AppUILanguage

    var body: some View {
        HStack(spacing: 4) {
            ForEach(OpenFileZoomPreference.allCases) { option in
                GeneralSegmentButton(
                    id: option.rawValue,
                    title: option.title(language: language),
                    systemImage: option.systemImage,
                    isSelected: selection == option.rawValue
                ) {
                    selection = option.rawValue
                }
            }
        }
        .padding(3)
        .background(VellumColors.backgroundDeepColor.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct LanguageSegmentedControl: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppUILanguage.allCases) { language in
                GeneralSegmentButton(
                    id: language.rawValue,
                    title: language.displayName,
                    systemImage: language.systemImage,
                    isSelected: selection == language.rawValue
                ) {
                    selection = language.rawValue
                }
            }
        }
        .labelStyle(.titleOnly)
        .padding(3)
        .background(VellumColors.backgroundDeepColor.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct GeneralSegmentButton: View {
    let id: String
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? VellumColors.foregroundColor : VellumColors.mutedColor)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(background, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isSelected ? VellumColors.borderColor.opacity(0.65) : .clear, lineWidth: 1)
                }
                .shadow(color: .black.opacity(isSelected ? 0.14 : 0), radius: 1, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .settingsControl(id, isSelected: isSelected, action: action)
        .onHover { isHovered = $0 }
    }

    private var background: Color {
        if isSelected {
            return VellumColors.panelElevatedColor
        }
        return isHovered ? VellumColors.panelColor : .clear
    }
}

private struct HighlightColorPicker: View {
    @Binding var selection: String
    let language: AppUILanguage

    var body: some View {
        HStack(spacing: 7) {
            ForEach(HighlightColor.allCases) { color in
                HighlightColorButton(
                    color: color,
                    isSelected: selection == color.rawValue,
                    language: language
                ) {
                    selection = color.rawValue
                    NotificationCenter.default.post(
                        name: VellumAppNotification.highlightColorPreferenceChanged,
                        object: nil,
                        userInfo: ["color": color.rawValue]
                    )
                }
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 34)
        .background(VellumColors.backgroundDeepColor.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct HighlightColorButton: View {
    let color: HighlightColor
    let isSelected: Bool
    let language: AppUILanguage
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.swatchColor)
                .frame(width: 18, height: 18)
                .overlay {
                    Circle()
                        .stroke(VellumColors.backgroundDeepColor.opacity(0.55), lineWidth: 1)
                }
                .padding(5)
                .background(
                    isSelected || isHovered ? VellumColors.selectionColor.opacity(isSelected ? 0.78 : 0.45) : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSelected ? VellumColors.foregroundColor.opacity(0.65) : .clear, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .settingsControl(color.rawValue, isSelected: isSelected, action: action)
        .help(color.helpText(language: language))
        .onHover { isHovered = $0 }
    }
}

private struct TogglePill: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isOn ? VellumColors.blueColor : VellumColors.panelElevatedColor)
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? VellumColors.foregroundColor : VellumColors.mutedColor)
                    .frame(width: 14, height: 14)
                    .padding(3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isOn ? VellumColors.blueColor.opacity(0.65) : VellumColors.borderColor.opacity(0.7), lineWidth: 1)
            }
    }
}

struct GeneralActionButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .regular))
            .foregroundStyle(VellumColors.foregroundColor)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                configuration.isPressed
                ? VellumColors.selectionColor.opacity(0.72)
                : (isHovered ? VellumColors.panelColor : VellumColors.panelColor.opacity(0.35)),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(VellumColors.borderColor.opacity(isHovered ? 0.8 : 0.4), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}
