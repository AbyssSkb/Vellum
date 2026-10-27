import SwiftUI

public struct AISettingsView: View {
    @AppStorage(AppPreferenceKeys.appLanguage) private var appLanguage = AppUILanguage.systemDefault().rawValue
    @ObservedObject private var navigation: SettingsNavigation

    public init(navigation: SettingsNavigation = SettingsNavigation()) {
        self.navigation = navigation
    }

    public var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            VellumDivider(axis: .vertical)

            Group {
                switch navigation.page {
                case .general:
                    GeneralSettingsView(page: .general)
                case .reading:
                    GeneralSettingsView(page: .reading)
                case .dictionary:
                    GeneralSettingsView(page: .dictionary)
                case .aiProviders:
                    AIProviderSettingsDetailView()
                case .aiExplanation:
                    AISettingsDetailView(page: .explanation)
                case .aiConversation:
                    AISettingsDetailView(page: .conversation)
                case .shortcuts:
                    ShortcutSettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VellumColors.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .foregroundStyle(VellumColors.foregroundColor)
        .tint(VellumColors.blueColor)
        .preferredColorScheme(.dark)
        .environment(\.appUILanguage, language)
        .environmentObject(navigation)
        .background(SettingsKeyboardBridge(navigation: navigation))
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
                    .foregroundStyle(VellumColors.foregroundColor)

                Text(language.text(.settings))
                    .font(.system(size: 12))
                    .foregroundStyle(VellumColors.mutedColor)
            }
            .padding(.horizontal, 18)

            VStack(alignment: .leading, spacing: 16) {
                sidebarGroup([.general, .reading, .dictionary])

                VStack(alignment: .leading, spacing: 5) {
                    Text(language.text(.ai))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(VellumColors.mutedColor.opacity(0.8))
                        .padding(.horizontal, 10)
                    sidebarGroup([.aiProviders, .aiExplanation, .aiConversation])
                }

                sidebarGroup([.shortcuts])
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 16)

            sidebarGroup([.about])
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
        }
        .frame(width: 192)
        .background(VellumColors.backgroundDeepColor)
        .ignoresSafeArea()
    }

    private func sidebarGroup(_ pages: [SettingsPage]) -> some View {
        VStack(spacing: 3) {
            ForEach(pages) { page in
                SettingsSidebarRow(
                    section: page,
                    isSelected: navigation.page == page,
                    isFocused: navigation.isSidebarFocused && navigation.page == page
                ) {
                    navigation.selectPage(page)
                    navigation.focusSidebar()
                }
            }
        }
    }

}

public enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case reading
    case dictionary
    case aiProviders
    case aiExplanation
    case aiConversation
    case shortcuts
    case about

    public var id: String { rawValue }

    func title(language: AppUILanguage) -> String {
        switch self {
        case .general:
            return language.text(.general)
        case .reading:
            return language.text(.reading)
        case .dictionary:
            return language.text(.localDictionary)
        case .about:
            return language.text(.aboutAndUpdates)
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
        case .reading:
            return "book"
        case .dictionary:
            return "character.book.closed"
        case .about:
            return "info.circle"
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
    @EnvironmentObject private var navigation: SettingsNavigation
    let section: SettingsPage
    let isSelected: Bool
    let isFocused: Bool
    let action: () -> Void
    @State private var isHovered = false
    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 17)
                    .foregroundStyle(isFocused ? VellumColors.blueColor : VellumColors.mutedColor)

                Text(section.title(language: language))
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? VellumColors.foregroundColor : VellumColors.mutedColor)

                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 34)
            .background(
                isSelected ? VellumColors.selectionColor.opacity(0.65) : (isHovered ? VellumColors.panelColor : .clear),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isFocused ? VellumColors.blueColor.opacity(0.8) : .clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($hasKeyboardFocus)
        .focusEffectDisabled()
        .settingsSidebarItem(section, focused: $hasKeyboardFocus)
        .onChange(of: hasKeyboardFocus) { _, focused in
            if focused { navigation.didFocusSidebar(section) }
        }
        .onHover { isHovered = $0 }
    }
}
