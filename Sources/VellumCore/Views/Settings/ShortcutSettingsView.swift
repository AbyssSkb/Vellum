import SwiftUI

struct ShortcutSettingsView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(TokyoNight.cyanColor)
                        .frame(width: 36, height: 36)
                        .background(TokyoNight.panelElevatedColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(TokyoNight.borderColor.opacity(0.75), lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Shortcuts")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(TokyoNight.foregroundColor)

                        Text("Keyboard commands available in the reader.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(TokyoNight.mutedColor)
                    }

                    Spacer()
                }

                ForEach(ShortcutCatalog.groups) { group in
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
