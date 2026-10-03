import SwiftUI

public struct AISettingsView: View {
    @AppStorage(AppPreferenceKeys.appLanguage) private var appLanguage = AppUILanguage.systemDefault().rawValue
    @State private var selection: SettingsSection = .general

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            TokyoNightDivider(axis: .vertical)

            Group {
                switch selection {
                case .general:
                    GeneralSettingsView()
                case .aiProviders:
                    AIProviderSettingsDetailView()
                case .aiExplanation:
                    AISettingsDetailView(page: .explanation)
                case .aiConversation:
                    AISettingsDetailView(page: .conversation)
                case .shortcuts:
                    ShortcutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TokyoNight.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .foregroundStyle(TokyoNight.foregroundColor)
        .tint(TokyoNight.blueColor)
        .preferredColorScheme(.dark)
        .environment(\.appUILanguage, language)
        .ignoresSafeArea()
    }

    private var language: AppUILanguage {
        AppUILanguage.saved(rawValue: appLanguage)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Color.clear
                .frame(height: 46)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Vellum")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Text(language.text(.settings))
                    .font(.system(size: 12))
                    .foregroundStyle(TokyoNight.mutedColor)
            }
            .padding(.horizontal, 18)

            VStack(spacing: 3) {
                ForEach(SettingsSection.allCases) { section in
                    SettingsSidebarRow(
                        section: section,
                        isSelected: selection == section
                    ) {
                        selection = section
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()
        }
        .frame(width: 212)
        .background(TokyoNight.backgroundDeepColor)
        .ignoresSafeArea()
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case aiProviders
    case aiExplanation
    case aiConversation
    case shortcuts

    var id: String { rawValue }

    func title(language: AppUILanguage) -> String {
        switch self {
        case .general:
            return language.text(.general)
        case .aiProviders:
            return language.text(.aiProviders)
        case .aiExplanation:
            return language.text(.aiExplanation)
        case .aiConversation:
            return language.text(.aiConversation)
        case .shortcuts:
            return language.text(.shortcuts)
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .aiProviders:
            return "building.2"
        case .aiExplanation:
            return "sparkles"
        case .aiConversation:
            return "bubble.left.and.bubble.right"
        case .shortcuts:
            return "keyboard"
        }
    }
}

private struct SettingsSidebarRow: View {
    @Environment(\.appUILanguage) private var language
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 17)
                    .foregroundStyle(isSelected ? TokyoNight.foregroundColor : TokyoNight.mutedColor)

                Text(section.title(language: language))
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 34)
            .background(isSelected ? TokyoNight.panelElevatedColor.opacity(0.75) : (isHovered ? TokyoNight.panelColor : .clear))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
