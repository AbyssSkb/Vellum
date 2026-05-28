enum ShortcutCatalog {
    static let groups: [ShortcutGroup] = [
        ShortcutGroup(
            title: "Files and Tabs",
            systemImage: "doc.on.doc",
            items: [
                ShortcutItem(keys: ["o"], action: "Open PDF in current tab"),
                ShortcutItem(keys: ["O"], action: "Open PDFs in new tabs"),
                ShortcutItem(keys: ["x"], action: "Close current tab"),
                ShortcutItem(keys: ["X"], action: "Restore closed PDF"),
                ShortcutItem(keys: ["[", "]"], action: "Switch tabs"),
                ShortcutItem(keys: ["H", "L"], action: "Switch tabs"),
                ShortcutItem(keys: ["gt", "gT"], action: "Switch tabs"),
                ShortcutItem(keys: ["Cmd O", "Cmd W"], action: "Open PDF or close tab"),
                ShortcutItem(keys: ["Cmd [", "Cmd ]"], action: "Switch tabs")
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
                ShortcutItem(keys: ["Space"], action: "Move forward one page"),
                ShortcutItem(keys: ["gg", "G", "[num]G"], action: "Jump to first, last, or numbered page"),
                ShortcutItem(keys: ["Ctrl O", "Ctrl I"], action: "Jump backward or forward")
            ]
        ),
        ShortcutGroup(
            title: "Search",
            systemImage: "magnifyingglass",
            items: [
                ShortcutItem(keys: ["/"], action: "Start search"),
                ShortcutItem(keys: ["Enter"], action: "Commit search query"),
                ShortcutItem(keys: ["Esc"], action: "Cancel search or clear search state"),
                ShortcutItem(keys: ["n", "N"], action: "Jump to next or previous match"),
                ShortcutItem(keys: ["v"], action: "Turn active match into text selection"),
                ShortcutItem(keys: ["y"], action: "Copy active match when available")
            ]
        ),
        ShortcutGroup(
            title: "View",
            systemImage: "rectangle.expand.vertical",
            items: [
                ShortcutItem(keys: ["=", "+", "-"], action: "Smooth zoom"),
                ShortcutItem(keys: ["z"], action: "Fit width"),
                ShortcutItem(keys: ["0"], action: "Fit page"),
                ShortcutItem(keys: ["Tab", "t"], action: "Toggle contents"),
                ShortcutItem(keys: ["Hold Tab"], action: "Open page overview")
            ]
        ),
        ShortcutGroup(
            title: "Page Overview",
            systemImage: "square.grid.3x3",
            items: [
                ShortcutItem(keys: ["Hold Tab"], action: "Enter page overview"),
                ShortcutItem(keys: ["h", "l"], action: "Move to previous or next page"),
                ShortcutItem(keys: ["k", "j"], action: "Move to previous or next row"),
                ShortcutItem(keys: ["Release Tab"], action: "Close overview at selected page")
            ]
        ),
        ShortcutGroup(
            title: "Highlights and AI",
            systemImage: "highlighter",
            items: [
                ShortcutItem(keys: ["m"], action: "Highlight selection"),
                ShortcutItem(keys: ["y"], action: "Copy selected text"),
                ShortcutItem(keys: ["c"], action: "Cycle highlight color"),
                ShortcutItem(keys: ["d"], action: "Delete highlight under selection"),
                ShortcutItem(keys: ["a"], action: "Explain selected text or highlight")
            ]
        ),
        ShortcutGroup(
            title: "AI Explanation",
            systemImage: "sparkles",
            items: [
                ShortcutItem(keys: ["j", "k"], action: "Scroll explanation"),
                ShortcutItem(keys: ["m"], action: "Save explained text as highlight"),
                ShortcutItem(keys: ["c"], action: "Cycle highlight color"),
                ShortcutItem(keys: ["Esc"], action: "Dismiss explanation")
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
                ShortcutItem(keys: ["Enter"], action: "Jump to selected item"),
                ShortcutItem(keys: ["Tab"], action: "Hide contents")
            ]
        )
    ]
}
