import SwiftUI

struct ShortcutSettingsView: View {
    @Environment(\.appUILanguage) private var language

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(TokyoNight.mutedColor)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text(.shortcuts))
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(TokyoNight.foregroundColor)

                        Text(language.text(.shortcutsHeaderSubtitle))
                            .font(.system(size: 12.5))
                            .foregroundStyle(TokyoNight.mutedColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
                .padding(.bottom, 4)

                ForEach(ShortcutCatalog.groups(language: language)) { group in
                    ShortcutGroupCard(group: group)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TokyoNight.backgroundColor)
        .background(SettingsScrollChromeConfigurator())
    }
}
