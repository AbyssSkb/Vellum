import SwiftUI

struct ShortcutGroupCard: View {
    let group: ShortcutGroup

    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                ForEach(group.items) { item in
                    ShortcutRow(item: item)

                    if item.id != group.items.last?.id {
                        Divider()
                    }
                }
            }
        } label: {
            Label(group.title, systemImage: group.systemImage)
                .font(.headline)
        }
    }
}
