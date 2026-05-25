import SwiftUI

struct ShortcutSettingsView: View {
    private let groups = ShortcutCatalog.groups

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shortcuts")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(TokyoNight.foregroundColor)

                    Text("Vim-style keyboard map")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TokyoNight.mutedColor)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(TokyoNight.panelColor.opacity(0.78))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(TokyoNight.borderColor.opacity(0.32))
                    .frame(height: 1)
            }

            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 250), spacing: 14),
                        GridItem(.flexible(minimum: 250), spacing: 14)
                    ],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(groups) { group in
                        ShortcutGroupCard(group: group)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
            }
        }
        .background(TokyoNight.backgroundColor)
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
                .foregroundStyle(TokyoNight.foregroundColor.opacity(0.9))
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: group.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TokyoNight.blueColor)
                    .frame(width: 18)

                Text(group.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Spacer(minLength: 0)
            }
            .padding(.bottom, 2)

            VStack(spacing: 0) {
                ForEach(group.items) { item in
                    ShortcutRow(item: item)

                    if item.id != group.items.last?.id {
                        Rectangle()
                            .fill(TokyoNight.borderColor.opacity(0.2))
                            .frame(height: 1)
                    }
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(TokyoNight.panelColor.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TokyoNight.borderColor.opacity(0.34), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ShortcutKeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(TokyoNight.foregroundColor)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(TokyoNight.backgroundDeepColor.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(TokyoNight.borderColor.opacity(0.55), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
