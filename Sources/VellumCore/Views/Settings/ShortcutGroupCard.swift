import SwiftUI

struct ShortcutGroupCard: View {
    let group: ShortcutGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(group.title, systemImage: group.systemImage)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(TokyoNight.mutedColor)

            VStack(spacing: 0) {
                ForEach(group.items) { item in
                    ShortcutRow(item: item)

                    if item.id != group.items.last?.id {
                        TokyoNightDivider(axis: .horizontal)
                            .opacity(0.75)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
