import SwiftUI

struct HighlightToolbar: View {
    @Environment(\.appUILanguage) private var language
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
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isSelected ? TokyoNight.selectionColor : isHovered ? TokyoNight.panelElevatedColor : .clear)
                            .frame(width: 28, height: 28)

                        Circle()
                            .fill(color.swatchColor)
                            .frame(width: isSelected ? 12 : 10, height: isSelected ? 12 : 10)
                            .opacity(isSelected || isHovered ? 1 : 0.68)
                    }
                    .frame(width: 34, height: 34)
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
        .background(TokyoNight.backgroundColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(TokyoNight.foregroundColor.opacity(0.05), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .frame(height: 38)
        .animation(.easeInOut(duration: 0.12), value: hoveredColor)
    }
}
