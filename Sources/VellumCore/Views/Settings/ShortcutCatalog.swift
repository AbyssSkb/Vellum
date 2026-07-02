enum ShortcutCatalog {
    static func groups(language: AppUILanguage) -> [ShortcutGroup] {
        switch language {
        case .english:
            return englishGroups
        case .chinese:
            return chineseGroups
        }
    }

    private static let englishGroups: [ShortcutGroup] = [
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
                ShortcutItem(keys: ["U", "D"], action: "Extra large smooth scroll"),
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
                ShortcutItem(keys: ["a"], action: "Explain selected text or highlight"),
                ShortcutItem(keys: ["A"], action: "Search AI explanations"),
                ShortcutItem(keys: ["i"], action: "Chat with AI about selection"),
                ShortcutItem(keys: ["I"], action: "Search AI conversations")
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
            title: "AI Conversation",
            systemImage: "bubble.left.and.bubble.right",
            items: [
                ShortcutItem(keys: ["i"], action: "Open conversation for selection"),
                ShortcutItem(keys: ["Enter"], action: "Send message"),
                ShortcutItem(keys: ["Shift Enter"], action: "Insert newline"),
                ShortcutItem(keys: ["Esc"], action: "Close conversation")
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

    private static let chineseGroups: [ShortcutGroup] = [
        ShortcutGroup(
            title: "文件与标签页",
            systemImage: "doc.on.doc",
            items: [
                ShortcutItem(keys: ["o"], action: "在当前标签页打开 PDF"),
                ShortcutItem(keys: ["O"], action: "在新标签页打开 PDF"),
                ShortcutItem(keys: ["x"], action: "关闭当前标签页"),
                ShortcutItem(keys: ["X"], action: "恢复已关闭的 PDF"),
                ShortcutItem(keys: ["[", "]"], action: "切换标签页"),
                ShortcutItem(keys: ["H", "L"], action: "切换标签页"),
                ShortcutItem(keys: ["gt", "gT"], action: "切换标签页"),
                ShortcutItem(keys: ["Cmd O", "Cmd W"], action: "打开 PDF 或关闭标签页"),
                ShortcutItem(keys: ["Cmd [", "Cmd ]"], action: "切换标签页")
            ]
        ),
        ShortcutGroup(
            title: "阅读",
            systemImage: "arrow.up.and.down",
            items: [
                ShortcutItem(keys: ["j", "k"], action: "平滑滚动"),
                ShortcutItem(keys: ["u", "d"], action: "大幅平滑滚动"),
                ShortcutItem(keys: ["U", "D"], action: "超大幅平滑滚动"),
                ShortcutItem(keys: ["h", "l"], action: "横向滚动"),
                ShortcutItem(keys: ["f", "b"], action: "精确翻一页"),
                ShortcutItem(keys: ["Space"], action: "向前翻一页"),
                ShortcutItem(keys: ["gg", "G", "[num]G"], action: "跳到首页、末页或指定页"),
                ShortcutItem(keys: ["Ctrl O", "Ctrl I"], action: "向后或向前跳转")
            ]
        ),
        ShortcutGroup(
            title: "搜索",
            systemImage: "magnifyingglass",
            items: [
                ShortcutItem(keys: ["/"], action: "开始搜索"),
                ShortcutItem(keys: ["Enter"], action: "确认搜索词"),
                ShortcutItem(keys: ["Esc"], action: "取消搜索或清除搜索状态"),
                ShortcutItem(keys: ["n", "N"], action: "跳到下一个或上一个匹配项"),
                ShortcutItem(keys: ["v"], action: "把当前匹配项变成文本选择"),
                ShortcutItem(keys: ["y"], action: "复制当前匹配项")
            ]
        ),
        ShortcutGroup(
            title: "视图",
            systemImage: "rectangle.expand.vertical",
            items: [
                ShortcutItem(keys: ["=", "+", "-"], action: "平滑缩放"),
                ShortcutItem(keys: ["z"], action: "适合宽度"),
                ShortcutItem(keys: ["0"], action: "适合整页"),
                ShortcutItem(keys: ["Tab", "t"], action: "切换目录"),
                ShortcutItem(keys: ["Hold Tab"], action: "打开页面概览")
            ]
        ),
        ShortcutGroup(
            title: "页面概览",
            systemImage: "square.grid.3x3",
            items: [
                ShortcutItem(keys: ["Hold Tab"], action: "进入页面概览"),
                ShortcutItem(keys: ["h", "l"], action: "移动到上一页或下一页"),
                ShortcutItem(keys: ["k", "j"], action: "移动到上一行或下一行"),
                ShortcutItem(keys: ["Release Tab"], action: "在选中页关闭概览")
            ]
        ),
        ShortcutGroup(
            title: "高亮与 AI",
            systemImage: "highlighter",
            items: [
                ShortcutItem(keys: ["m"], action: "高亮选中文本"),
                ShortcutItem(keys: ["y"], action: "复制选中文本"),
                ShortcutItem(keys: ["c"], action: "切换高亮颜色"),
                ShortcutItem(keys: ["d"], action: "删除选中位置下的高亮"),
                ShortcutItem(keys: ["a"], action: "解释选中文本或高亮"),
                ShortcutItem(keys: ["i"], action: "围绕选中文本进行 AI 对话")
            ]
        ),
        ShortcutGroup(
            title: "AI 解释",
            systemImage: "sparkles",
            items: [
                ShortcutItem(keys: ["j", "k"], action: "滚动解释内容"),
                ShortcutItem(keys: ["m"], action: "把解释文本保存为高亮"),
                ShortcutItem(keys: ["c"], action: "切换高亮颜色"),
                ShortcutItem(keys: ["Esc"], action: "关闭解释")
            ]
        ),
        ShortcutGroup(
            title: "AI 对话",
            systemImage: "bubble.left.and.bubble.right",
            items: [
                ShortcutItem(keys: ["i"], action: "为选中文本打开对话"),
                ShortcutItem(keys: ["Cmd Enter"], action: "发送消息"),
                ShortcutItem(keys: ["Esc"], action: "关闭对话")
            ]
        ),
        ShortcutGroup(
            title: "文本选择",
            systemImage: "selection.pin.in.out",
            items: [
                ShortcutItem(keys: ["h", "j", "k", "l"], action: "移动选择端点"),
                ShortcutItem(keys: ["w", "b", "e"], action: "按单词移动"),
                ShortcutItem(keys: ["Esc"], action: "清除文本选择")
            ]
        ),
        ShortcutGroup(
            title: "目录",
            systemImage: "list.bullet.indent",
            items: [
                ShortcutItem(keys: ["j", "k"], action: "移动目录选择"),
                ShortcutItem(keys: ["h", "l"], action: "折叠或展开"),
                ShortcutItem(keys: ["Enter"], action: "跳到选中的条目"),
                ShortcutItem(keys: ["Tab"], action: "隐藏目录")
            ]
        )
    ]
}
