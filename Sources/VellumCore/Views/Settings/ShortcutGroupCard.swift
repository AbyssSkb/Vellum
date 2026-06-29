import SwiftUI

struct ShortcutGroupCard: View {
    let group: ShortcutGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(group.title, systemImage: group.systemImage)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(TokyoNight.foregroundColor)

            VStack(spacing: 0) {
                ForEach(group.items) { item in
                    ShortcutRow(item: item)

                    if item.id != group.items.last?.id {
                        TokyoNightDivider(axis: .horizontal)
                            .opacity(0.6)
                    }
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TokyoNight.panelColor.opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TokyoNight.borderColor.opacity(0.62), lineWidth: 1)
        }
    }
}
