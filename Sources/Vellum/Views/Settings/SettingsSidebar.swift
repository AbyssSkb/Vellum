import SwiftUI

struct SettingsSidebar: View {
    @Binding var selectedCategory: SettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Vellum")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Text("Settings")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TokyoNight.mutedColor)
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 8)

            ForEach(SettingsCategory.allCases) { category in
                Button {
                    selectedCategory = category
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: category.systemImage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(selectedCategory == category ? TokyoNight.blueColor : TokyoNight.mutedColor)
                            .frame(width: 20)

                        Text(category.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TokyoNight.foregroundColor)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(selectedCategory == category ? TokyoNight.selectionColor.opacity(0.92) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(selectedCategory == category ? TokyoNight.blueColor.opacity(0.22) : Color.clear, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
            }

            Spacer()
        }
        .background {
            ZStack {
                SidebarVisualEffectBackground()
                TokyoNight.backgroundDeepColor.opacity(0.68)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(TokyoNight.borderColor.opacity(0.42))
                .frame(width: 1)
        }
    }
}
