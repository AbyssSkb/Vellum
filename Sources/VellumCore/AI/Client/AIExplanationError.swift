import Foundation

enum AIExplanationError: LocalizedError {
    case invalidBaseURL
    case missingModel
    case missingAPIKey
    case missingCodexExecutable
    case noSelection
    case noHighlightedText
    case emptyResponse
    case server(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "AI base_url 无效，请在设置里填写完整的 http/https 地址。"
        case .missingModel:
            return "AI 模型名称为空，请先在设置里填写模型名称。"
        case .missingAPIKey:
            return "AI API Key 为空，请先在设置里填写 API Key。"
        case .missingCodexExecutable:
            return "Codex 路径为空，请先在设置里填写 codex 可执行文件路径。"
        case .noSelection:
            return "请先选中一段文字。"
        case .noHighlightedText:
            return "当前选区没有命中任何高亮。"
        case .emptyResponse:
            return "AI 没有返回可用解释。"
        case .server(let message):
            return message
        case .transport(let message):
            return message
        }
    }
}
