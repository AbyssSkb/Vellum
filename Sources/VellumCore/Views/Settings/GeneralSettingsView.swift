import SwiftUI

struct GeneralSettingsView: View {
    @Environment(\.appUILanguage) private var language
    @AppStorage(AppPreferenceKeys.appLanguage) private var appLanguage = AppUILanguage.systemDefault().rawValue
    @AppStorage(AppPreferenceKeys.automaticallyCheckForUpdates) private var automaticallyCheckForUpdates = true
    @AppStorage(AppPreferenceKeys.defaultPDFOpenMode) private var defaultPDFOpenMode = DefaultPDFOpenModePreference.currentTab.rawValue
    @AppStorage(AppPreferenceKeys.defaultHighlightColor) private var defaultHighlightColor = HighlightColor.yellow.rawValue
    @AppStorage(AppPreferenceKeys.doubleClickTranslatesSelection) private var doubleClickTranslatesSelection = true
    @AppStorage(AppPreferenceKeys.restorePreviousTabs) private var restorePreviousTabs = false
    @AppStorage(AppPreferenceKeys.openFileZoomBehavior) private var openFileZoomBehavior = OpenFileZoomPreference.fitWidth.rawValue
    @State private var logStatusMessage: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                interfaceSection
                startupSection
                readingSection
                updatesSection
                diagnosticsSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TokyoNight.backgroundColor)
        .background(SettingsScrollChromeConfigurator())
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "gearshape")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(TokyoNight.mutedColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(language.text(.general))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Text(language.text(.generalHeaderSubtitle))
                    .font(.system(size: 12.5))
                    .foregroundStyle(TokyoNight.mutedColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.bottom, 4)
    }

    private var interfaceSection: some View {
        GeneralSettingsPanel(title: language.text(.appUI), systemImage: "globe") {
            GeneralOptionRow(title: language.text(.appLanguage), subtitle: language.text(.appLanguageSubtitle)) {
                LanguageSegmentedControl(selection: $appLanguage)
            }
        }
    }

    private var startupSection: some View {
        GeneralSettingsPanel(title: language.text(.startup), systemImage: "power") {
            VStack(spacing: 0) {
                GeneralToggleRow(
                    title: language.text(.restorePreviousTabs),
                    subtitle: language.text(.restorePreviousTabsSubtitle),
                    isOn: $restorePreviousTabs
                )

                GeneralOptionRow(title: language.text(.defaultOpenMode), subtitle: language.text(.defaultOpenModeSubtitle)) {
                    GeneralSegmentedControl(
                        selection: $defaultPDFOpenMode,
                        options: DefaultPDFOpenModePreference.allCases,
                        language: language
                    )
                }
            }
        }
    }

    private var readingSection: some View {
        GeneralSettingsPanel(title: language.text(.reading), systemImage: "doc.text.magnifyingglass") {
            VStack(spacing: 0) {
                GeneralToggleRow(
                    title: language.text(.doubleClickTranslate),
                    subtitle: language.text(.doubleClickTranslateSubtitle),
                    isOn: $doubleClickTranslatesSelection
                )

                GeneralOptionRow(title: language.text(.openFileZoom), subtitle: language.text(.openFileZoomSubtitle)) {
                    OpenFileZoomSegmentedControl(selection: $openFileZoomBehavior, language: language)
                }

                GeneralOptionRow(title: language.text(.defaultHighlight), subtitle: language.text(.defaultHighlightSubtitle)) {
                    HighlightColorPicker(selection: $defaultHighlightColor, language: language)
                }
            }
        }
    }

    private var updatesSection: some View {
        GeneralSettingsPanel(title: language.text(.updates), systemImage: "arrow.triangle.2.circlepath") {
            VStack(spacing: 0) {
                GeneralToggleRow(
                    title: language.text(.automaticallyCheck),
                    subtitle: language.text(.automaticallyCheckSubtitle),
                    isOn: $automaticallyCheckForUpdates
                )

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text(.currentVersion))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(TokyoNight.foregroundColor)

                        Text(appVersionText)
                            .font(.system(size: 12))
                            .foregroundStyle(TokyoNight.mutedColor)
                    }

                    Spacer()

                    Button {
                        NotificationCenter.default.post(name: VellumAppNotification.checkForUpdatesRequested, object: nil)
                    } label: {
                        Label(language.text(.checkNow), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GeneralActionButtonStyle())
                }
                .padding(.vertical, 12)
                .frame(minHeight: 54)
                .overlay(alignment: .bottom) {
                    TokyoNight.borderColor.opacity(0.45).frame(height: 1)
                }
            }
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version?.nilIfEmpty ?? "Development"
    }

    private var diagnosticsSection: some View {
        GeneralSettingsPanel(title: language.text(.diagnostics), systemImage: "waveform.path.ecg") {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text(.aiRequestLogs))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(TokyoNight.foregroundColor)

                        Text(language.text(.aiRequestLogsSubtitle))
                            .font(.system(size: 12))
                            .foregroundStyle(TokyoNight.mutedColor)
                            .fixedSize(horizontal: false, vertical: true)

                        if let logStatusMessage {
                            Text(logStatusMessage)
                                .font(.system(size: 11.5))
                                .foregroundStyle(TokyoNight.mutedColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            openAIRequestLog()
                        } label: {
                            Label(language.text(.openLog), systemImage: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(GeneralActionButtonStyle())

                        Button {
                            clearAIRequestLog()
                        } label: {
                            Label(language.text(.clearLog), systemImage: "trash")
                        }
                        .buttonStyle(GeneralActionButtonStyle())
                    }
                }
                .padding(.vertical, 12)
                .frame(minHeight: 62)
                .overlay(alignment: .bottom) {
                    TokyoNight.borderColor.opacity(0.45).frame(height: 1)
                }
            }
        }
    }

    private func openAIRequestLog() {
        do {
            try AIRequestLogger.openLog()
            logStatusMessage = AIRequestLogger.logFileURL.path
        } catch {
            logStatusMessage = language.text(.aiLogsFailed(error.localizedDescription))
        }
    }

    private func clearAIRequestLog() {
        do {
            try AIRequestLogger.clearLog()
            logStatusMessage = language.text(.aiLogsCleared)
        } catch {
            logStatusMessage = language.text(.aiLogsFailed(error.localizedDescription))
        }
    }
}

private struct GeneralSettingsPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(TokyoNight.mutedColor)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GeneralToggleRow: View {
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
                        .foregroundStyle(TokyoNight.foregroundColor)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(TokyoNight.mutedColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                TogglePill(isOn: isOn)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 58)
            .background(isHovered ? TokyoNight.panelColor : .clear)
            .overlay(alignment: .bottom) {
                TokyoNight.borderColor.opacity(0.45).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct GeneralOptionRow<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(TokyoNight.mutedColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            content
        }
        .padding(.vertical, 12)
        .frame(minHeight: 58)
        .overlay(alignment: .bottom) {
            TokyoNight.borderColor.opacity(0.45).frame(height: 1)
        }
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
                    title: option.title(language: language),
                    systemImage: option.systemImage,
                    isSelected: selection == option.rawValue
                ) {
                    selection = option.rawValue
                }
            }
        }
        .padding(3)
        .background(TokyoNight.backgroundDeepColor.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct OpenFileZoomSegmentedControl: View {
    @Binding var selection: String
    let language: AppUILanguage

    var body: some View {
        HStack(spacing: 4) {
            ForEach(OpenFileZoomPreference.allCases) { option in
                GeneralSegmentButton(
                    title: option.title(language: language),
                    systemImage: option.systemImage,
                    isSelected: selection == option.rawValue
                ) {
                    selection = option.rawValue
                }
            }
        }
        .padding(3)
        .background(TokyoNight.backgroundDeepColor.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct LanguageSegmentedControl: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppUILanguage.allCases) { language in
                GeneralSegmentButton(
                    title: language.displayName,
                    systemImage: language.systemImage,
                    isSelected: selection == language.rawValue
                ) {
                    selection = language.rawValue
                }
            }
        }
        .padding(3)
        .background(TokyoNight.backgroundDeepColor.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct GeneralSegmentButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? TokyoNight.foregroundColor : TokyoNight.mutedColor)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(background, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isSelected ? TokyoNight.blueColor.opacity(0.5) : .clear, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var background: Color {
        if isSelected {
            return TokyoNight.panelElevatedColor
        }
        return isHovered ? TokyoNight.panelColor : .clear
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
        .background(TokyoNight.backgroundDeepColor.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                        .stroke(TokyoNight.backgroundDeepColor.opacity(0.55), lineWidth: 1)
                }
                .padding(5)
                .background(
                    isSelected || isHovered ? TokyoNight.selectionColor.opacity(isSelected ? 0.78 : 0.45) : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSelected ? TokyoNight.blueColor.opacity(0.65) : .clear, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(color.helpText(language: language))
        .onHover { isHovered = $0 }
    }
}

private struct TogglePill: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isOn ? TokyoNight.blueColor : TokyoNight.panelElevatedColor)
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? TokyoNight.foregroundColor : TokyoNight.mutedColor)
                    .frame(width: 14, height: 14)
                    .padding(3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isOn ? TokyoNight.blueColor.opacity(0.65) : TokyoNight.borderColor.opacity(0.7), lineWidth: 1)
            }
    }
}

private struct GeneralActionButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .regular))
            .foregroundStyle(TokyoNight.foregroundColor)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                configuration.isPressed
                ? TokyoNight.selectionColor.opacity(0.72)
                : (isHovered ? TokyoNight.panelElevatedColor : TokyoNight.panelColor),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(TokyoNight.borderColor.opacity(isHovered ? 0.9 : 0.65), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}
