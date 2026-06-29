import SwiftUI

struct ShortcutRow: View {
    let item: ShortcutItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.action)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(TokyoNight.foregroundColor)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                ForEach(item.keys, id: \.self) { key in
                    ShortcutKeyCap(text: key)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
