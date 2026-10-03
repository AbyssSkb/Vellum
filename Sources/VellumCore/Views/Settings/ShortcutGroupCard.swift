import SwiftUI

struct ShortcutGroupCard: View {
    let group: ShortcutGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Label(group.title, systemImage: group.systemImage)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(TokyoNight.mutedColor)
                    .layoutPriority(1)

                TokyoNight.borderColor.opacity(0.45)
                    .frame(height: 0.5)
            }

            VStack(spacing: 0) {
                ForEach(group.items) { item in
                    ShortcutRow(item: item)

                    if item.id != group.items.last?.id {
                        TokyoNightDivider(axis: .horizontal)
                            .opacity(0.35)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
