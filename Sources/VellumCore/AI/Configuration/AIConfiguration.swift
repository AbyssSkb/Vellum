import Foundation

enum AISettingsKeys {
    static let providerID = "AIProviderID"
    static let providerFormat = "AIProviderFormat"
    static let baseURL = "AIBaseURL"
    static let model = "AIModel"
    static let apiKey = "AIApiKey"
}

enum AIProviderFormat: String, CaseIterable, Identifiable, Sendable {
    case openAICompatible
    case anthropicMessages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAICompatible:
            return "OpenAI-compatible"
        case .anthropicMessages:
            return "Anthropic Messages"
        }
    }

    var description: String {
        switch self {
        case .openAICompatible:
            return "Uses /chat/completions and /models."
        case .anthropicMessages:
            return "Uses Anthropic /messages and /models."
        }
    }
}

struct AIProviderPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let baseURL: String
    let defaultModel: String
    let format: AIProviderFormat

    static let customID = "custom"

    static let presets: [AIProviderPreset] = [
        AIProviderPreset(
            id: "openai",
            name: "OpenAI",
            summary: "Official OpenAI API",
            baseURL: "https://api.openai.com/v1",
            defaultModel: "gpt-4.1-mini",
            format: .openAICompatible
        ),
        AIProviderPreset(
            id: "deepseek",
            name: "DeepSeek",
            summary: "OpenAI-compatible DeepSeek API",
            baseURL: "https://api.deepseek.com",
            defaultModel: "deepseek-v4-flash",
            format: .openAICompatible
        ),
        AIProviderPreset(
            id: "anthropic",
            name: "Anthropic",
            summary: "Official Claude Messages API",
            baseURL: "https://api.anthropic.com/v1",
            defaultModel: "claude-3-5-haiku-latest",
            format: .anthropicMessages
        ),
        AIProviderPreset(
            id: customID,
            name: "Custom",
            summary: "Bring your own compatible endpoint",
            baseURL: AIConfiguration.defaultBaseURL,
            defaultModel: AIConfiguration.defaultModel,
            format: .openAICompatible
        )
    ]
}

struct AIConfiguration: Sendable {
    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4.1-mini"

    let baseURL: URL
    let model: String
    let apiKey: String
    let providerFormat: AIProviderFormat

    static func current(requireModel: Bool = true) throws -> AIConfiguration {
        let defaults = UserDefaults.standard
        let providerFormat = defaults.string(forKey: AISettingsKeys.providerFormat)
            .flatMap(AIProviderFormat.init(rawValue:))
            ?? .openAICompatible
        let baseURLString = defaults.string(forKey: AISettingsKeys.baseURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? defaultBaseURL
        let model = defaults.string(forKey: AISettingsKeys.model)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? defaultModel
        let apiKey = defaults.string(forKey: AISettingsKeys.apiKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return try AIConfiguration(
            baseURLString: baseURLString,
            model: model,
            apiKey: apiKey,
            providerFormat: providerFormat,
            requireModel: requireModel
        )
    }

    init(
        baseURLString: String,
        model: String,
        apiKey: String,
        providerFormat: AIProviderFormat = .openAICompatible,
        requireModel: Bool = true
    ) throws {
        let trimmedBaseURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let baseURL = URL(string: trimmedBaseURL),
              let scheme = baseURL.scheme,
              scheme.hasPrefix("http") else {
            throw AIExplanationError.invalidBaseURL
        }

        guard !requireModel || !trimmedModel.isEmpty else {
            throw AIExplanationError.missingModel
        }

        guard !trimmedAPIKey.isEmpty else {
            throw AIExplanationError.missingAPIKey
        }

        self.baseURL = baseURL
        self.model = trimmedModel
        self.apiKey = trimmedAPIKey
        self.providerFormat = providerFormat
    }

    var chatCompletionsURL: URL {
        endpointURL("chat/completions")
    }

    var messagesURL: URL {
        endpointURL("messages")
    }

    var modelsURL: URL {
        endpointURL("models")
    }

    var supportsSiliconFlowThinkingControls: Bool {
        baseURL.host?.lowercased().contains("siliconflow") == true
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
