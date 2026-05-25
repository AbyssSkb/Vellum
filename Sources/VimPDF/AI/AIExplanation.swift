import Foundation
import PDFKit

enum AISettingsKeys {
    static let baseURL = "AIBaseURL"
    static let model = "AIModel"
    static let apiKey = "AIApiKey"
}

struct AIConfiguration: Sendable {
    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o-mini"

    let baseURL: URL
    let model: String
    let apiKey: String

    static func current(requireModel: Bool = true) throws -> AIConfiguration {
        let defaults = UserDefaults.standard
        let baseURLString = defaults.string(forKey: AISettingsKeys.baseURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? defaultBaseURL
        let model = defaults.string(forKey: AISettingsKeys.model)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? defaultModel
        let apiKey = defaults.string(forKey: AISettingsKeys.apiKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard let baseURL = URL(string: baseURLString),
              let scheme = baseURL.scheme,
              scheme.hasPrefix("http") else {
            throw AIExplanationError.invalidBaseURL
        }

        guard !requireModel || !model.isEmpty else {
            throw AIExplanationError.missingModel
        }

        guard !apiKey.isEmpty else {
            throw AIExplanationError.missingAPIKey
        }

        return AIConfiguration(baseURL: baseURL, model: model, apiKey: apiKey)
    }

    var chatCompletionsURL: URL {
        endpointURL("chat/completions")
    }

    var modelsURL: URL {
        endpointURL("models")
    }

    private func endpointURL(_ endpoint: String) -> URL {
        var url = baseURL
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if path.hasSuffix(endpoint) {
            return url
        }

        if path.hasSuffix("chat/completions") {
            url.deleteLastPathComponent()
            url.deleteLastPathComponent()
        } else if path.hasSuffix("models") {
            url.deleteLastPathComponent()
        }

        for component in endpoint.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        return url
    }
}

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

enum AIExplanationAnnotation {
    static let marker = "VimPDF AI Explanation v1"

    static func encode(_ explanation: String) -> String {
        "\(marker)\n\n\(explanation.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    static func decode(_ contents: String?) -> String? {
        guard let contents,
              contents.hasPrefix(marker) else { return nil }

        let text = contents
            .dropFirst(marker.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text)
    }
}

enum HighlightAnnotationMetadata {
    private static let groupKey = PDFAnnotationKey(rawValue: "VimPDFHighlightGroup")

    static func groupID(for annotation: PDFAnnotation) -> String? {
        annotation.value(forAnnotationKey: groupKey) as? String
    }

    static func setGroupID(_ groupID: String, for annotation: PDFAnnotation) {
        annotation.setValue(groupID, forAnnotationKey: groupKey)
    }
}

enum AIExplanationError: LocalizedError {
    case invalidBaseURL
    case missingModel
    case missingAPIKey
    case noSelection
    case noHighlightedText
    case emptyResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "AI base_url 无效，请在设置里填写完整的 http/https 地址。"
        case .missingModel:
            return "AI 模型名称为空，请先在设置里填写模型名称。"
        case .missingAPIKey:
            return "AI API Key 为空，请先在设置里填写 API Key。"
        case .noSelection:
            return "请先选中一段文字。"
        case .noHighlightedText:
            return "当前选区没有命中任何高亮。"
        case .emptyResponse:
            return "AI 没有返回可用解释。"
        case .server(let message):
            return message
        }
    }
}

enum AIExplanationClient {
    static func testConnection(configuration: AIConfiguration) async throws -> String {
        var request = URLRequest(url: configuration.chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body = ChatCompletionRequest(
            model: configuration.model,
            messages: [
                ChatMessage(role: "system", content: "Reply with exactly: OK"),
                ChatMessage(role: "user", content: "Ping")
            ],
            temperature: 0
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data: data, response: response)

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard completion.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty != nil else {
            throw AIExplanationError.emptyResponse
        }

        return "模型可用：\(configuration.model)"
    }

    static func fetchModels(configuration: AIConfiguration) async throws -> [String] {
        var request = URLRequest(url: configuration.modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data: data, response: response)

        let models = try JSONDecoder().decode(ModelListResponse.self, from: data)
        return models.data
            .map(\.id)
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func explain(context: AIExplanationContext, configuration: AIConfiguration) async throws -> String {
        var request = URLRequest(url: configuration.chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let body = ChatCompletionRequest(
            model: configuration.model,
            messages: [
                ChatMessage(
                    role: "system",
                    content: "你是 VimPDF 的阅读助手，擅长解释 PDF 中被高亮的文字。你必须基于用户提供的原文和上下文回答，不要编造。"
                ),
                ChatMessage(role: "user", content: context.prompt)
            ],
            temperature: 0.2
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data: data, response: response)
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let text = completion.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw AIExplanationError.emptyResponse
        }

        return text
    }

    static func streamExplanation(
        context: AIExplanationContext,
        configuration: AIConfiguration,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        var request = URLRequest(url: configuration.chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let body = ChatCompletionRequest(
            model: configuration.model,
            messages: [
                ChatMessage(
                    role: "system",
                    content: "你是 VimPDF 的阅读助手。你必须基于用户提供的原文和上下文回答，重点解释用户选中文本本身，不要默认总结整段。"
                ),
                ChatMessage(role: "user", content: context.prompt)
            ],
            temperature: 0.2,
            stream: true
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try validate(response: response)

        var fullText = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }

            let payload = line
                .dropFirst("data:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard payload != "[DONE]", let data = payload.data(using: .utf8) else {
                break
            }

            guard let chunk = try? JSONDecoder().decode(ChatCompletionStreamChunk.self, from: data),
                  let delta = chunk.choices.first?.delta.content,
                  !delta.isEmpty else {
                continue
            }

            fullText += delta
            await MainActor.run {
                onChunk(delta)
            }
        }

        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIExplanationError.emptyResponse
        }

        return trimmed
    }

    private static func validate(data: Data, response: URLResponse) throws {
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? "AI 请求失败，HTTP \(httpResponse.statusCode)。"
            throw AIExplanationError.server(message)
        }
    }

    private static func validate(response: URLResponse) throws {
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw AIExplanationError.server("AI 请求失败，HTTP \(httpResponse.statusCode)。")
        }
    }

    private struct ChatCompletionRequest: Encodable {
        var model: String
        var messages: [ChatMessage]
        var temperature: Double
        var stream: Bool? = nil
    }

    private struct ChatMessage: Codable {
        var role: String
        var content: String
    }

    private struct ChatCompletionResponse: Decodable {
        var choices: [Choice]

        struct Choice: Decodable {
            var message: ChatMessage
        }
    }

    private struct ChatCompletionStreamChunk: Decodable {
        var choices: [Choice]

        struct Choice: Decodable {
            var delta: Delta
        }

        struct Delta: Decodable {
            var content: String?
        }
    }

    private struct ModelListResponse: Decodable {
        var data: [Model]

        struct Model: Decodable {
            var id: String
        }
    }
}
