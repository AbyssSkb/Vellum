import Foundation

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

        return try AIConfiguration(
            baseURLString: baseURLString,
            model: model,
            apiKey: apiKey,
            requireModel: requireModel
        )
    }

    init(baseURLString: String, model: String, apiKey: String, requireModel: Bool = true) throws {
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
    }

    var chatCompletionsURL: URL {
        endpointURL("chat/completions")
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
