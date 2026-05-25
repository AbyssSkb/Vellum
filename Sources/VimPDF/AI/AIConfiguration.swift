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
