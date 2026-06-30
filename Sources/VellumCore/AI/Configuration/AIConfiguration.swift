import Foundation

enum AISettingsKeys {
    static let providerID = "AIProviderID"
    static let providerFormat = "AIProviderFormat"
    static let baseURL = "AIBaseURL"
    static let model = "AIModel"
    static let apiKey = "AIApiKey"

    static func baseURLKey(for providerID: String) -> String {
        providerScopedKey("BaseURL", providerID: providerID)
    }

    static func modelKey(for providerID: String) -> String {
        providerScopedKey("Model", providerID: providerID)
    }

    static func apiKeyKey(for providerID: String) -> String {
        providerScopedKey("APIKey", providerID: providerID)
    }

    private static func providerScopedKey(_ name: String, providerID: String) -> String {
        "AIProvider.\(providerID).\(name)"
    }
}

enum AIProviderFormat: String, CaseIterable, Identifiable, Sendable {
    case openAICompatible
    case anthropicMessages
    case codexCLI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAICompatible:
            return "OpenAI-compatible"
        case .anthropicMessages:
            return "Anthropic Messages"
        case .codexCLI:
            return "Codex"
        }
    }

    var description: String {
        switch self {
        case .openAICompatible:
            return "Uses /chat/completions and /models."
        case .anthropicMessages:
            return "Uses Anthropic /messages and /models."
        case .codexCLI:
            return "Uses local Codex with model list and streaming."
        }
    }

    var usesCodexExecutable: Bool {
        self == .codexCLI
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
            summary: "Official OpenAI API.",
            baseURL: "https://api.openai.com/v1",
            defaultModel: "gpt-4.1-mini",
            format: .openAICompatible
        ),
        AIProviderPreset(
            id: "deepseek",
            name: "DeepSeek",
            summary: "DeepSeek API.",
            baseURL: "https://api.deepseek.com",
            defaultModel: "deepseek-v4-flash",
            format: .openAICompatible
        ),
        AIProviderPreset(
            id: "siliconflow",
            name: "SiliconFlow",
            summary: "SiliconFlow API.",
            baseURL: "https://api.siliconflow.cn/v1",
            defaultModel: "deepseek-ai/DeepSeek-V3",
            format: .openAICompatible
        ),
        AIProviderPreset(
            id: "anthropic",
            name: "Anthropic",
            summary: "Official Claude API.",
            baseURL: "https://api.anthropic.com/v1",
            defaultModel: "claude-3-5-haiku-latest",
            format: .anthropicMessages
        ),
        AIProviderPreset(
            id: "codex-cli",
            name: "Codex",
            summary: "Local Codex.",
            baseURL: Self.defaultCodexExecutablePath,
            defaultModel: "",
            format: .codexCLI
        ),
        AIProviderPreset(
            id: customID,
            name: "Custom",
            summary: "Any OpenAI-compatible endpoint.",
            baseURL: AIConfiguration.defaultBaseURL,
            defaultModel: AIConfiguration.defaultModel,
            format: .openAICompatible
        )
    ]

    static func preset(for id: String) -> AIProviderPreset {
        presets.first { $0.id == id }
            ?? presets.first { $0.id == customID }!
    }

    private static var defaultCodexExecutablePath: String {
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/opt/homebrew/bin/codex"
    }
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
        let providerID = defaults.string(forKey: AISettingsKeys.providerID)
            ?? AIProviderPreset.presets.first?.id
            ?? AIProviderPreset.customID
        let provider = AIProviderPreset.preset(for: providerID)
        let baseURLString = providerScopedValue(
            forKey: AISettingsKeys.baseURLKey(for: provider.id),
            legacyKey: AISettingsKeys.baseURL,
            defaultValue: provider.baseURL,
            defaults: defaults
        )
        let model = providerScopedValue(
            forKey: AISettingsKeys.modelKey(for: provider.id),
            legacyKey: AISettingsKeys.model,
            defaultValue: provider.defaultModel,
            defaults: defaults
        )
        let apiKey = providerScopedValue(
            forKey: AISettingsKeys.apiKeyKey(for: provider.id),
            legacyKey: AISettingsKeys.apiKey,
            defaultValue: "",
            defaults: defaults
        )

        return try AIConfiguration(
            baseURLString: baseURLString,
            model: model,
            apiKey: apiKey,
            providerFormat: provider.format,
            requireModel: requireModel
        )
    }

    private static func providerScopedValue(
        forKey key: String,
        legacyKey: String,
        defaultValue: String,
        defaults: UserDefaults
    ) -> String {
        if defaults.object(forKey: key) != nil {
            let scopedValue = defaults.string(forKey: key) ?? ""
            return scopedValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return defaults.string(forKey: legacyKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? defaultValue
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

        if providerFormat.usesCodexExecutable {
            guard !trimmedBaseURL.isEmpty else {
                throw AIExplanationError.missingCodexExecutable
            }

            self.baseURL = URL(fileURLWithPath: trimmedBaseURL)
            self.model = trimmedModel
            self.apiKey = trimmedAPIKey
            self.providerFormat = providerFormat
            return
        }

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

    var codexExecutablePath: String {
        baseURL.path
    }

    var codexProfile: String {
        apiKey
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
