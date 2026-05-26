import Foundation

struct AIExplanationContext: Sendable {
    var selectedText: String
    var previousParagraph: String?
    var currentParagraph: String?
    var nextParagraph: String?
    var nearbyText: String
    var fileName: String
    var directoryName: String?
    var outlineTitle: String?
    var pageNumbers: [Int]

    var prompt: String {
        """
        用户正在阅读 PDF，并选中了一段文本。请根据上下文解释“选中文本本身”，不要默认总结整段，也不要加入与理解选中文本无关的项目。

        请严格按照这个 Markdown 模板输出。只有在规则明确要求省略某个标题时，才可以省略该标题。

        如果选中文本是单个英文单词或常见英文词形，请先输出：

        ### 音标
        给出常见英式和美式音标；如果无法可靠判断，只给一个常见音标并说明不确定。

        ### 中文翻译
        用自然中文翻译选中文本。只翻译选中文本本身。
        如果选中文本本来就是中文，或中文翻译不会增加理解价值，请完全省略“中文翻译”这个标题和内容。

        ### 上下文解释
        用中文解释它在当前上下文里的具体含义、指代对象、逻辑作用或可能的深层含义。只写能帮助理解选中文本的内容。

        输出要求：
        - 不要按“单词/短语/句子/段落”分类处理。
        - 如果选中文本是单个英文单词或常见英文词形，必须附上音标；不要给整句或短语编造音标。
        - 如果不需要翻译，省略“中文翻译”部分，不要写“无需翻译”。
        - 附近段落只用于消歧和补充背景；只讲有助于理解选中文本的内容，不要展开无关背景。
        - 保持简洁，优先给出能加深理解的解释；如果涉及数学公式，请保留 LaTeX 形式。
        - 如果上下文不足，请明确指出不确定点，不要编造。

        文件名：
        \(fileName)

        所在文件夹：
        \(directoryName ?? "未知")

        目录标题：
        \(outlineTitle ?? "未知")

        页码：
        \(pageNumbers.map(String.init).joined(separator: ", "))

        选中文本：
        \(selectedText)

        前一段：
        \(previousParagraph ?? "未能从 PDF 文本中稳定识别。")

        当前段落：
        \(currentParagraph ?? "未能从 PDF 文本中稳定识别。")

        后一段：
        \(nextParagraph ?? "未能从 PDF 文本中稳定识别。")

        附近可提取文本：
        \(nearbyText)
        """
    }
}
