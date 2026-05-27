import SwiftUI

struct HighlightToolbar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 7) {
            ForEach(HighlightColor.allCases) { color in
                let isSelected = appState.selectedHighlightColor == color

                Button {
                    appState.selectHighlightColor(color)
                } label: {
                    ZStack {
                        if isSelected {
                            Circle()
                                .fill(TokyoNight.foregroundColor.opacity(0.14))
                                .frame(width: 31, height: 31)
                            Circle()
                                .stroke(TokyoNight.foregroundColor, lineWidth: 2.5)
                                .frame(width: 27, height: 27)
                        }

                        Circle()
                            .fill(color.swatchColor)
                            .frame(width: isSelected ? 20 : 12, height: isSelected ? 20 : 12)
                            .overlay(
                                Circle()
                                    .stroke(
                                        isSelected ? TokyoNight.backgroundDeepColor.opacity(0.9) : TokyoNight.borderColor.opacity(0.55),
                                        lineWidth: isSelected ? 1.5 : 1
                                    )
                            )
                    }
                    .frame(width: 32, height: 32)
                    .animation(.easeInOut(duration: 0.12), value: isSelected)
                }
                .buttonStyle(.plain)
                .help(color.helpText)
                .accessibilityLabel(color.helpText)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint("Select this highlight color")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(TokyoNight.panelElevatedColor.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(TokyoNight.borderColor.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
