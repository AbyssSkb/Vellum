import SwiftUI

struct ShortcutKeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(VellumColors.foregroundColor)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(VellumColors.panelColor, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(VellumColors.borderColor.opacity(0.65), lineWidth: 1)
            )
    }
}
