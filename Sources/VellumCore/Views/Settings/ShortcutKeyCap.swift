import SwiftUI

struct ShortcutKeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(TokyoNight.foregroundColor)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(TokyoNight.backgroundDeepColor.opacity(0.88), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(TokyoNight.borderColor.opacity(0.7), lineWidth: 1)
            )
    }
}
