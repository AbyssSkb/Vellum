import Foundation

struct CodexModelInfo: Equatable, Sendable {
    let id: String
    let supportedReasoningEfforts: [String]
}

struct CodexSettingsSnapshot: Equatable, Sendable {
    let models: [CodexModelInfo]

    func model(for configuration: AIConfiguration) -> CodexModelInfo? {
        models.first { $0.id == configuration.model }
    }
}
