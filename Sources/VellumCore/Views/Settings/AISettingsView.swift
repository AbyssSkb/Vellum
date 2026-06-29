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
                case .ai:
                    AISettingsDetailView()
                case .shortcuts:
                    ShortcutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TokyoNight.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TokyoNight.borderColor.opacity(0.95), lineWidth: 1)
        }
        .foregroundStyle(TokyoNight.foregroundColor)
        .tint(TokyoNight.cyanColor)
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Text(language.text(.settings))
                    .font(.system(size: 12))
                    .foregroundStyle(TokyoNight.mutedColor)
            }
            .padding(.horizontal, 18)

            VStack(spacing: 6) {
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
        .frame(width: 188)
        .background(TokyoNight.backgroundDeepColor)
        .ignoresSafeArea()
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case ai
    case shortcuts

    var id: String { rawValue }

    func title(language: AppUILanguage) -> String {
        switch self {
        case .general:
            return language.text(.general)
        case .ai:
            return language.text(.ai)
        case .shortcuts:
            return language.text(.shortcuts)
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .ai:
            return "sparkles"
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 17)
                    .foregroundStyle(isSelected ? TokyoNight.cyanColor : TokyoNight.mutedColor)

                Text(section.title(language: language))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 34)
            .background(isSelected ? TokyoNight.selectionColor.opacity(0.58) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
