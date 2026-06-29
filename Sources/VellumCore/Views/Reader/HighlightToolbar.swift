import SwiftUI

struct HighlightToolbar: View {
    @EnvironmentObject private var appState: AppState
    @State private var hoveredColor: HighlightColor?

    var body: some View {
        HStack(spacing: 5) {
            ForEach(HighlightColor.allCases) { color in
                let isSelected = appState.selectedHighlightColor == color
                let isHovered = hoveredColor == color

                Button {
                    appState.selectHighlightColor(color)
                } label: {
                    ZStack {
                        if isSelected || isHovered {
                            Circle()
                                .fill(TokyoNight.foregroundColor.opacity(isSelected ? 0.14 : 0.08))
                                .frame(width: 31, height: 31)
                        }

                        if isSelected {
                            Circle()
                                .stroke(TokyoNight.foregroundColor, lineWidth: 2.5)
                                .frame(width: 27, height: 27)
                        }

                        Circle()
                            .fill(color.swatchColor)
                            .frame(width: isSelected ? 20 : (isHovered ? 17 : 14), height: isSelected ? 20 : (isHovered ? 17 : 14))
                            .overlay(
                                Circle()
                                    .stroke(
                                        isSelected ? TokyoNight.backgroundDeepColor.opacity(0.9) : TokyoNight.borderColor.opacity(0.55),
                                        lineWidth: isSelected ? 1.5 : 1
                                    )
                            )
                    }
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
                    .animation(.easeInOut(duration: 0.12), value: isSelected)
                    .animation(.easeInOut(duration: 0.1), value: isHovered)
                }
                .buttonStyle(.plain)
                .help(color.helpText)
                .accessibilityLabel(color.helpText)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint("Select this highlight color")
                .onHover { hoveredColor = $0 ? color : (hoveredColor == color ? nil : hoveredColor) }
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 38)
        .background(TokyoNight.panelElevatedColor.opacity(hoveredColor == nil ? 0.7 : 0.86))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(TokyoNight.borderColor.opacity(hoveredColor == nil ? 0.55 : 0.74), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .animation(.easeInOut(duration: 0.12), value: hoveredColor)
    }
}
