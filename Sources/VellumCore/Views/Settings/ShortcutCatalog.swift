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
                ShortcutItem(keys: ["o"], action: "Open PDF when no text is selected"),
                ShortcutItem(keys: ["O"], action: "Open PDFs in new tabs"),
                ShortcutItem(keys: ["Z"], action: "Fuzzy search PDFs in your home folder"),
                ShortcutItem(keys: ["x"], action: "Close current tab"),
                ShortcutItem(keys: ["X"], action: "Restore closed PDF"),
                ShortcutItem(keys: ["[", "]"], action: "Switch tabs"),
                ShortcutItem(keys: ["H", "L"], action: "Switch tabs"),
                ShortcutItem(keys: ["gt", "gT"], action: "Switch tabs from reader"),
                ShortcutItem(keys: ["T"], action: "Search open tabs"),
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
                ShortcutItem(keys: ["10j", "5f", "3n"], action: "Repeat a reader motion with a count (up to 1,000)"),
                ShortcutItem(keys: ["gg", "G", "[num]G", "[num]gg"], action: "Jump to first, last, or numbered page"),
                ShortcutItem(keys: ["F"], action: "Type a visible PDF link's label to follow it"),
                ShortcutItem(keys: ["p"], action: "Type a visible internal link's label to preview its target"),
                ShortcutItem(keys: ["Ctrl O", "Ctrl I"], action: "Jump backward or forward")
            ]
        ),
        ShortcutGroup(
            title: "Local Dictionary",
            systemImage: "character.book.closed",
            items: [
                ShortcutItem(keys: ["K"], action: "Look up the selected word (Shift+K)"),
                ShortcutItem(keys: ["j", "k"], action: "Scroll dictionary entry"),
                ShortcutItem(keys: ["h", "l"], action: "Scroll dictionary horizontally"),
                ShortcutItem(keys: ["d", "u"], action: "Scroll half a dictionary viewport"),
                ShortcutItem(keys: ["f", "b", "Space"], action: "Scroll a dictionary viewport"),
                ShortcutItem(keys: ["gg", "G"], action: "Go to the top or bottom of the entry"),
                ShortcutItem(keys: ["Esc"], action: "Close dictionary")
            ]
        ),
        ShortcutGroup(
            title: "Link Preview",
            systemImage: "rectangle.on.rectangle",
            items: [
                ShortcutItem(keys: ["j", "k"], action: "Scroll focused preview"),
                ShortcutItem(keys: ["h", "l"], action: "Scroll preview horizontally"),
                ShortcutItem(keys: ["d", "u", "f", "b"], action: "Scroll preview in larger steps"),
                ShortcutItem(keys: ["=", "+", "-"], action: "Zoom preview"),
                ShortcutItem(keys: ["p", "Enter"], action: "Close preview and jump to the target"),
                ShortcutItem(keys: ["x"], action: "Close focused preview and focus reader"),
                ShortcutItem(keys: ["Esc"], action: "Close preview and keep your reading position")
            ]
        ),
        ShortcutGroup(
            title: "Search",
            systemImage: "magnifyingglass",
            items: [
                ShortcutItem(keys: ["/"], action: "Start search"),
                ShortcutItem(keys: ["*"], action: "Search selected text"),
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
                ShortcutItem(keys: ["t"], action: "Show or hide contents"),
                ShortcutItem(keys: ["Tab"], action: "Switch reader and contents focus; open contents if hidden"),
                ShortcutItem(keys: ["Hold Tab"], action: "Open gallery from reader or contents")
            ]
        ),
        ShortcutGroup(
            title: "Page Gallery",
            systemImage: "square.grid.3x3",
            items: [
                ShortcutItem(keys: ["Hold Tab"], action: "Enter page gallery"),
                ShortcutItem(keys: ["h", "l"], action: "Move to previous or next page"),
                ShortcutItem(keys: ["k", "j"], action: "Move backward or forward three pages"),
                ShortcutItem(keys: ["Release Tab"], action: "Commit selected page and focus reader"),
                ShortcutItem(keys: ["Esc"], action: "Cancel gallery; restore original position and focus")
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
                ShortcutItem(keys: ["M"], action: "Search highlighted text or page number"),
                ShortcutItem(keys: ["gn", "gN"], action: "Select next or previous highlight"),
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
                ShortcutItem(keys: ["s"], action: "Type a visible word prefix, then its label to select"),
                ShortcutItem(keys: ["o"], action: "Switch the selection endpoint being adjusted"),
                ShortcutItem(keys: ["gv"], action: "Restore the last text selection"),
                ShortcutItem(keys: ["h", "j", "k", "l"], action: "Move selection endpoint"),
                ShortcutItem(keys: ["w", "b", "e"], action: "Move by word"),
                ShortcutItem(keys: ["^", "$"], action: "Move to first text / end of visual line"),
                ShortcutItem(keys: ["3w", "3j"], action: "Repeat a selection motion with a count"),
                ShortcutItem(keys: ["Esc"], action: "Clear text selection")
            ]
        ),
        ShortcutGroup(
            title: "Contents",
            systemImage: "list.bullet.indent",
            items: [
                ShortcutItem(keys: ["j", "k", "[num]j", "[num]k"], action: "Move outline selection"),
                ShortcutItem(keys: ["h", "←", "[num]h"], action: "Close containing folds (same as zc)"),
                ShortcutItem(keys: ["l", "→", "[num]l"], action: "Open a closed fold; otherwise select next row"),
                ShortcutItem(keys: ["gg", "G", "[num]G", "[num]gg"], action: "Select first, last, or numbered row"),
                ShortcutItem(keys: ["d", "u"], action: "Move half a viewport"),
                ShortcutItem(keys: ["D", "U", "f", "b", "Space"], action: "Move a full viewport"),
                ShortcutItem(keys: ["zo", "zc", "[num]zo", "[num]zc"], action: "Open or close folds at selection"),
                ShortcutItem(keys: ["zr", "zm", "[num]zr", "[num]zm"], action: "Increase or decrease global fold level"),
                ShortcutItem(keys: ["zO"], action: "Open first closed fold at selection and all its descendants"),
                ShortcutItem(keys: ["zC"], action: "Close all folds containing selection"),
                ShortcutItem(keys: ["zR", "zM"], action: "Open or close all folds"),
                ShortcutItem(keys: ["Option →", "Option ←"], action: "Expand or collapse entire branch (leaf: parent)"),
                ShortcutItem(keys: ["Option Shift →", "Option Shift ←"], action: "Expand or collapse all branches"),
                ShortcutItem(keys: ["Enter"], action: "Jump to selected item and focus reader"),
                ShortcutItem(keys: ["Tab"], action: "Focus reader, keeping contents open"),
                ShortcutItem(keys: ["Esc"], action: "Clear pending input; otherwise focus reader"),
                ShortcutItem(keys: ["t"], action: "Hide contents and focus reader"),
                ShortcutItem(keys: ["H", "L", "[", "]"], action: "Switch files from contents")
            ]
        )
    ]

    private static let chineseGroups: [ShortcutGroup] = [
        ShortcutGroup(
            title: "文件与标签页",
            systemImage: "doc.on.doc",
            items: [
                ShortcutItem(keys: ["o"], action: "未选中文字时打开 PDF"),
                ShortcutItem(keys: ["O"], action: "在新标签页打开 PDF"),
                ShortcutItem(keys: ["Z"], action: "模糊搜索主目录中的 PDF"),
                ShortcutItem(keys: ["x"], action: "关闭当前标签页"),
                ShortcutItem(keys: ["X"], action: "恢复已关闭的 PDF"),
                ShortcutItem(keys: ["[", "]"], action: "切换标签页"),
                ShortcutItem(keys: ["H", "L"], action: "切换标签页"),
                ShortcutItem(keys: ["gt", "gT"], action: "从阅读区切换标签页"),
                ShortcutItem(keys: ["T"], action: "搜索已打开的标签页"),
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
                ShortcutItem(keys: ["10j", "5f", "3n"], action: "按次数执行正文移动（最多 1,000 次）"),
                ShortcutItem(keys: ["gg", "G", "[num]G", "[num]gg"], action: "跳到首页、末页或指定页"),
                ShortcutItem(keys: ["F"], action: "输入可见 PDF 链接的标签以打开"),
                ShortcutItem(keys: ["p"], action: "输入可见内部链接的标签以预览目标"),
                ShortcutItem(keys: ["Ctrl O", "Ctrl I"], action: "向后或向前跳转")
            ]
        ),
        ShortcutGroup(
            title: "本地词典",
            systemImage: "character.book.closed",
            items: [
                ShortcutItem(keys: ["K"], action: "查询选中的单词（Shift+K）"),
                ShortcutItem(keys: ["j", "k"], action: "滚动词典内容"),
                ShortcutItem(keys: ["h", "l"], action: "左右滚动词典内容"),
                ShortcutItem(keys: ["d", "u"], action: "滚动半个词典视口"),
                ShortcutItem(keys: ["f", "b", "Space"], action: "滚动一个词典视口"),
                ShortcutItem(keys: ["gg", "G"], action: "移到词条顶部或底部"),
                ShortcutItem(keys: ["Esc"], action: "关闭词典")
            ]
        ),
        ShortcutGroup(
            title: "链接预览",
            systemImage: "rectangle.on.rectangle",
            items: [
                ShortcutItem(keys: ["j", "k"], action: "滚动获得焦点的预览"),
                ShortcutItem(keys: ["h", "l"], action: "横向滚动预览"),
                ShortcutItem(keys: ["d", "u", "f", "b"], action: "大幅滚动预览"),
                ShortcutItem(keys: ["=", "+", "-"], action: "缩放预览"),
                ShortcutItem(keys: ["p", "Enter"], action: "关闭预览并跳转到目标位置"),
                ShortcutItem(keys: ["x"], action: "关闭获得焦点的预览并回到正文"),
                ShortcutItem(keys: ["Esc"], action: "关闭预览并保留正文位置")
            ]
        ),
        ShortcutGroup(
            title: "搜索",
            systemImage: "magnifyingglass",
            items: [
                ShortcutItem(keys: ["/"], action: "开始搜索"),
                ShortcutItem(keys: ["*"], action: "搜索选中文字"),
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
                ShortcutItem(keys: ["t"], action: "显示或隐藏目录"),
                ShortcutItem(keys: ["Tab"], action: "切换正文与目录焦点，目录隐藏时先打开"),
                ShortcutItem(keys: ["Hold Tab"], action: "从正文或目录打开画廊")
            ]
        ),
        ShortcutGroup(
            title: "沉浸画廊",
            systemImage: "square.grid.3x3",
            items: [
                ShortcutItem(keys: ["Hold Tab"], action: "进入沉浸画廊"),
                ShortcutItem(keys: ["h", "l"], action: "移动到上一页或下一页"),
                ShortcutItem(keys: ["k", "j"], action: "向前或向后移动三页"),
                ShortcutItem(keys: ["Release Tab"], action: "确认选中页并聚焦正文"),
                ShortcutItem(keys: ["Esc"], action: "取消画廊，恢复原阅读位置和焦点")
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
                ShortcutItem(keys: ["M"], action: "搜索高亮原文或页码"),
                ShortcutItem(keys: ["gn", "gN"], action: "选中下一条或上一条高亮"),
                ShortcutItem(keys: ["a"], action: "解释选中文本或高亮"),
                ShortcutItem(keys: ["A"], action: "搜索 AI 解释历史"),
                ShortcutItem(keys: ["i"], action: "围绕选中文本进行 AI 对话"),
                ShortcutItem(keys: ["I"], action: "搜索 AI 对话历史")
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
                ShortcutItem(keys: ["Enter"], action: "发送消息"),
                ShortcutItem(keys: ["Shift Enter"], action: "换行"),
                ShortcutItem(keys: ["Esc"], action: "关闭对话")
            ]
        ),
        ShortcutGroup(
            title: "文本选择",
            systemImage: "selection.pin.in.out",
            items: [
                ShortcutItem(keys: ["s"], action: "输入可见单词的开头，再按标签选中"),
                ShortcutItem(keys: ["o"], action: "切换正在调整的选区端点"),
                ShortcutItem(keys: ["gv"], action: "恢复上次文本选区"),
                ShortcutItem(keys: ["h", "j", "k", "l"], action: "移动选择端点"),
                ShortcutItem(keys: ["w", "b", "e"], action: "按单词移动"),
                ShortcutItem(keys: ["^", "$"], action: "移到视觉行首个文字／行尾"),
                ShortcutItem(keys: ["3w", "3j"], action: "按次数调整选区"),
                ShortcutItem(keys: ["Esc"], action: "清除文本选择")
            ]
        ),
        ShortcutGroup(
            title: "目录",
            systemImage: "list.bullet.indent",
            items: [
                ShortcutItem(keys: ["j", "k", "[num]j", "[num]k"], action: "移动目录选择"),
                ShortcutItem(keys: ["h", "←", "[num]h"], action: "折叠所选路径（等同 zc）"),
                ShortcutItem(keys: ["l", "→", "[num]l"], action: "展开收起的一层，否则移动到下一行"),
                ShortcutItem(keys: ["gg", "G", "[num]G", "[num]gg"], action: "选择首行、末行或指定行"),
                ShortcutItem(keys: ["d", "u"], action: "移动半个可见区域"),
                ShortcutItem(keys: ["D", "U", "f", "b", "Space"], action: "移动一个可见区域"),
                ShortcutItem(keys: ["zo", "zc", "[num]zo", "[num]zc"], action: "展开或折叠所选位置的指定层数"),
                ShortcutItem(keys: ["zr", "zm", "[num]zr", "[num]zm"], action: "增加或减少全局折叠级别"),
                ShortcutItem(keys: ["zO"], action: "展开所选路径上首个收起分支及其全部子项"),
                ShortcutItem(keys: ["zC"], action: "折叠包含所选位置的全部层级"),
                ShortcutItem(keys: ["zR", "zM"], action: "展开或折叠全部目录"),
                ShortcutItem(keys: ["Option →", "Option ←"], action: "展开或折叠整个分支（叶子条目作用于父项）"),
                ShortcutItem(keys: ["Option Shift →", "Option Shift ←"], action: "展开或折叠全部分支"),
                ShortcutItem(keys: ["Enter"], action: "跳到选中的条目并聚焦正文"),
                ShortcutItem(keys: ["Tab"], action: "聚焦正文，保留目录显示"),
                ShortcutItem(keys: ["Esc"], action: "清除待完成输入，否则聚焦正文"),
                ShortcutItem(keys: ["t"], action: "隐藏目录并聚焦正文"),
                ShortcutItem(keys: ["H", "L", "[", "]"], action: "从目录切换文件")
            ]
        )
    ]
}
