import SwiftUI

struct HighlightToolbar: View {
    @Environment(\.appUILanguage) private var language
    @EnvironmentObject private var appState: AppState
    @State private var hoveredColor: HighlightColor?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HighlightColor.allCases) { color in
                let isSelected = appState.selectedHighlightColor == color
                let isHovered = hoveredColor == color

                Button {
                    appState.selectHighlightColor(color)
                } label: {
                    ZStack {
                        Circle()
                            .fill(isHovered ? VellumColors.panelElevatedColor : .clear)
                            .frame(width: 26, height: 26)

                        if isSelected {
                            Circle()
                                .strokeBorder(VellumColors.mutedColor.opacity(0.55), lineWidth: 0.75)
                                .frame(width: 18, height: 18)
                        }

                        Circle()
                            .fill(color.swatchColor)
                            .frame(width: isSelected ? 12 : 10, height: isSelected ? 12 : 10)
                            .opacity(isSelected || isHovered ? 1 : 0.68)
                    }
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                    .animation(.easeInOut(duration: 0.12), value: isSelected)
                    .animation(.easeInOut(duration: 0.1), value: isHovered)
                }
                .buttonStyle(.plain)
                .help(color.helpText(language: language))
                .accessibilityLabel(color.helpText(language: language))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(language.text(.selectHighlightColorHint))
                .onHover { hoveredColor = $0 ? color : (hoveredColor == color ? nil : hoveredColor) }
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 34)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(VellumColors.borderColor.opacity(0.4))
                .frame(width: 0.5, height: 16)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(height: 38)
        .animation(.easeInOut(duration: 0.12), value: hoveredColor)
    }
}
