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

        请严格按照这个 Markdown 模板输出，不要增删标题：

        ### 中文翻译
        用自然中文翻译选中文本。只翻译选中文本本身。

        ### 上下文解释
        用中文解释它在当前上下文里的具体含义、指代对象、逻辑作用或可能的深层含义。只写能帮助理解选中文本的内容。

        输出要求：
        - 不要按“单词/短语/句子/段落”分类处理。
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
