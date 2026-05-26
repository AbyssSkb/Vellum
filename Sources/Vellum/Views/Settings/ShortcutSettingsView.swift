import SwiftUI

struct ShortcutSettingsView: View {
    private let groups = ShortcutCatalog.groups

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups) { group in
                    ShortcutGroupCard(group: group)
                }
            }
            .padding(20)
        }
    }
}

struct ShortcutGroup: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let items: [ShortcutItem]
}

struct ShortcutItem: Identifiable {
    let id = UUID()
    let keys: [String]
    let action: String
}

enum ShortcutCatalog {
    static let groups: [ShortcutGroup] = [
        ShortcutGroup(
            title: "Files and Tabs",
            systemImage: "doc.on.doc",
            items: [
                ShortcutItem(keys: ["o"], action: "Open PDF in current tab"),
                ShortcutItem(keys: ["O"], action: "Open PDF in new tab"),
                ShortcutItem(keys: ["x"], action: "Close current tab"),
                ShortcutItem(keys: ["X"], action: "Restore closed PDF"),
                ShortcutItem(keys: ["[", "]", "H", "L"], action: "Switch tabs")
            ]
        ),
        ShortcutGroup(
            title: "Reading",
            systemImage: "arrow.up.and.down",
            items: [
                ShortcutItem(keys: ["j", "k"], action: "Smooth scroll"),
                ShortcutItem(keys: ["u", "d"], action: "Large smooth scroll"),
                ShortcutItem(keys: ["h", "l"], action: "Horizontal scroll"),
                ShortcutItem(keys: ["f", "b"], action: "Move exactly one page"),
                ShortcutItem(keys: ["gg", "G", "[num]G"], action: "Jump to first, last, or numbered page"),
                ShortcutItem(keys: ["Ctrl O", "Ctrl I"], action: "Jump backward or forward")
            ]
        ),
        ShortcutGroup(
            title: "View",
            systemImage: "rectangle.expand.vertical",
            items: [
                ShortcutItem(keys: ["=", "-"], action: "Smooth zoom"),
                ShortcutItem(keys: ["z"], action: "Fit width"),
                ShortcutItem(keys: ["0"], action: "Fit page"),
                ShortcutItem(keys: ["Tab", "t"], action: "Toggle contents")
            ]
        ),
        ShortcutGroup(
            title: "Highlights and AI",
            systemImage: "highlighter",
            items: [
                ShortcutItem(keys: ["m"], action: "Highlight selection"),
                ShortcutItem(keys: ["c"], action: "Cycle highlight color"),
                ShortcutItem(keys: ["d"], action: "Delete selected highlight"),
                ShortcutItem(keys: ["a"], action: "Explain selected text")
            ]
        ),
        ShortcutGroup(
            title: "Text Selection",
            systemImage: "selection.pin.in.out",
            items: [
                ShortcutItem(keys: ["h", "j", "k", "l"], action: "Move selection endpoint"),
                ShortcutItem(keys: ["w", "b", "e"], action: "Move by word"),
                ShortcutItem(keys: ["Esc"], action: "Clear text selection")
            ]
        ),
        ShortcutGroup(
            title: "Contents",
            systemImage: "list.bullet.indent",
            items: [
                ShortcutItem(keys: ["j", "k"], action: "Move outline selection"),
                ShortcutItem(keys: ["h", "l"], action: "Collapse or expand"),
                ShortcutItem(keys: ["Enter"], action: "Jump to selected item")
            ]
        )
    ]
}

struct ShortcutRow: View {
    let item: ShortcutItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.action)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
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
