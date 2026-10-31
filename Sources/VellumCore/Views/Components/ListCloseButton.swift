import SwiftUI

struct ListCloseButton: View {
    @Environment(\.appUILanguage) private var language
    @State private var isHovered = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isHovered ? VellumColors.foregroundColor : VellumColors.mutedColor)
                .frame(width: 32, height: 28)
                .background(isHovered ? VellumColors.panelElevatedColor : VellumColors.panelColor,
                            in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(VellumColors.borderColor))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(language.text(.cancel))
        .accessibilityLabel(language.text(.cancel))
    }
}
