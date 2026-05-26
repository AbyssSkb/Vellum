import SwiftUI

struct ShortcutKeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(.separator.opacity(0.45), lineWidth: 1)
            )
    }
}
