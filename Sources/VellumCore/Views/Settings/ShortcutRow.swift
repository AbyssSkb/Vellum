import SwiftUI

struct ShortcutRow: View {
    let item: ShortcutItem

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(item.action)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(TokyoNight.foregroundColor)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                ForEach(item.keys, id: \.self) { key in
                    ShortcutKeyCap(text: key)
                }
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }
}
