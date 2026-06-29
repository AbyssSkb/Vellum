import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(AppPreferenceKeys.automaticallyCheckForUpdates) private var automaticallyCheckForUpdates = true
    @AppStorage(AppPreferenceKeys.defaultOpenMode) private var defaultOpenMode = DefaultOpenModePreference.currentTab.rawValue
    @AppStorage(AppPreferenceKeys.defaultHighlightColor) private var defaultHighlightColor = HighlightColor.yellow.rawValue
    @AppStorage(AppPreferenceKeys.doubleClickTranslatesSelection) private var doubleClickTranslatesSelection = true
    @AppStorage(AppPreferenceKeys.restorePreviousTabs) private var restorePreviousTabs = false
    @AppStorage(AppPreferenceKeys.openFileZoomBehavior) private var openFileZoomBehavior = OpenFileZoomPreference.fitWidth.rawValue

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                startupSection
                readingSection
                updatesSection
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
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(TokyoNight.cyanColor)
                .frame(width: 36, height: 36)
                .background(TokyoNight.panelElevatedColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TokyoNight.borderColor.opacity(0.75), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text("General")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Text("Set startup, reading, and update behavior.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(TokyoNight.mutedColor)
            }

            Spacer()
        }
    }

    private var startupSection: some View {
        GeneralSettingsPanel(title: "Startup", systemImage: "power") {
            VStack(spacing: 10) {
                GeneralToggleRow(
                    title: "Restore Previous Tabs",
                    subtitle: "Reopen PDFs and reading positions from the last session.",
                    isOn: $restorePreviousTabs
                )

                GeneralOptionRow(title: "Default Open Mode", subtitle: "Choose where the Open command places PDFs.") {
                    GeneralSegmentedControl(
                        selection: $defaultOpenMode,
                        options: DefaultOpenModePreference.allCases
                    )
                }
            }
        }
    }

    private var readingSection: some View {
        GeneralSettingsPanel(title: "Reading", systemImage: "doc.text.magnifyingglass") {
            VStack(spacing: 10) {
                GeneralToggleRow(
                    title: "Double-Click Translate",
                    subtitle: "Translate the selected word after a text double-click.",
                    isOn: $doubleClickTranslatesSelection
                )

                GeneralOptionRow(title: "Open File Zoom", subtitle: "Choose the initial zoom for newly opened PDFs.") {
                    OpenFileZoomSegmentedControl(selection: $openFileZoomBehavior)
                }

                GeneralOptionRow(title: "Default Highlight", subtitle: "Pick the highlight color used by new markings.") {
                    HighlightColorPicker(selection: $defaultHighlightColor)
                }
            }
        }
    }

    private var updatesSection: some View {
        GeneralSettingsPanel(title: "Updates", systemImage: "arrow.triangle.2.circlepath") {
            VStack(spacing: 10) {
                GeneralToggleRow(
                    title: "Automatically Check",
                    subtitle: "Look for new releases shortly after launch.",
                    isOn: $automaticallyCheckForUpdates
                )

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Current Version")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TokyoNight.foregroundColor)

                        Text(appVersionText)
                            .font(.system(size: 12))
                            .foregroundStyle(TokyoNight.mutedColor)
                    }

                    Spacer()

                    Button {
                        NotificationCenter.default.post(name: VellumAppNotification.checkForUpdatesRequested, object: nil)
                    } label: {
                        Label("Check Now", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GeneralActionButtonStyle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 54)
                .background(TokyoNight.backgroundDeepColor.opacity(0.56), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(TokyoNight.borderColor.opacity(0.48), lineWidth: 1)
                }
            }
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version?.nilIfEmpty ?? "Development"
    }
}

private struct GeneralSettingsPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(TokyoNight.foregroundColor)

            content
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TokyoNight.panelColor.opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TokyoNight.borderColor.opacity(0.62), lineWidth: 1)
        }
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
                        .font(.system(size: 13, weight: .semibold))
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 54)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(rowStroke, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isOn {
            return TokyoNight.selectionColor.opacity(isHovered ? 0.66 : 0.54)
        }
        return TokyoNight.backgroundDeepColor.opacity(isHovered ? 0.72 : 0.56)
    }

    private var rowStroke: Color {
        if isOn {
            return TokyoNight.cyanColor.opacity(isHovered ? 0.68 : 0.48)
        }
        return TokyoNight.borderColor.opacity(isHovered ? 0.72 : 0.48)
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
                    .font(.system(size: 13, weight: .semibold))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
        .background(TokyoNight.backgroundDeepColor.opacity(0.56), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(TokyoNight.borderColor.opacity(0.48), lineWidth: 1)
        }
    }
}

private struct GeneralSegmentedControl: View {
    @Binding var selection: String
    let options: [DefaultOpenModePreference]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                GeneralSegmentButton(
                    title: option.title,
                    systemImage: option.systemImage,
                    isSelected: selection == option.rawValue
                ) {
                    selection = option.rawValue
                }
            }
        }
        .padding(3)
        .background(TokyoNight.panelColor.opacity(0.86), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(TokyoNight.borderColor.opacity(0.54), lineWidth: 1)
        }
    }
}

private struct OpenFileZoomSegmentedControl: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(OpenFileZoomPreference.allCases) { option in
                GeneralSegmentButton(
                    title: option.title,
                    systemImage: option.systemImage,
                    isSelected: selection == option.rawValue
                ) {
                    selection = option.rawValue
                }
            }
        }
        .padding(3)
        .background(TokyoNight.panelColor.opacity(0.86), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(TokyoNight.borderColor.opacity(0.54), lineWidth: 1)
        }
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? TokyoNight.backgroundDeepColor : TokyoNight.foregroundColor)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(background, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var background: Color {
        if isSelected {
            return TokyoNight.cyanColor
        }
        return isHovered ? TokyoNight.selectionColor.opacity(0.55) : .clear
    }
}

private struct HighlightColorPicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 7) {
            ForEach(HighlightColor.allCases) { color in
                HighlightColorButton(
                    color: color,
                    isSelected: selection == color.rawValue
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
        .background(TokyoNight.panelColor.opacity(0.86), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(TokyoNight.borderColor.opacity(0.54), lineWidth: 1)
        }
    }
}

private struct HighlightColorButton: View {
    let color: HighlightColor
    let isSelected: Bool
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
                        .stroke(isSelected ? TokyoNight.cyanColor.opacity(0.78) : .clear, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(color.helpText)
        .onHover { isHovered = $0 }
    }
}

private struct TogglePill: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isOn ? TokyoNight.cyanColor : TokyoNight.panelElevatedColor)
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? TokyoNight.backgroundDeepColor : TokyoNight.mutedColor)
                    .frame(width: 14, height: 14)
                    .padding(3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isOn ? TokyoNight.cyanColor.opacity(0.65) : TokyoNight.borderColor.opacity(0.7), lineWidth: 1)
            }
    }
}

private struct GeneralActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(TokyoNight.foregroundColor)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                configuration.isPressed
                ? TokyoNight.selectionColor.opacity(0.72)
                : TokyoNight.panelElevatedColor.opacity(0.9),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(TokyoNight.borderColor.opacity(0.72), lineWidth: 1)
            }
    }
}
