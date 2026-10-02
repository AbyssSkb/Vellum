import Foundation

enum AIExplanationError: LocalizedError {
    case invalidBaseURL
    case missingModel
    case missingAPIKey
    case missingCodexExecutable
    case noSelection
    case noHighlightedText
    case emptyResponse
    case responseTruncated
    case streamEndedPrematurely
    case server(String)
    case transport(String)

    var errorDescription: String? {
        message(language: .saved())
    }

    func message(language: AppUILanguage) -> String {
        switch self {
        case .invalidBaseURL:
            return language.text(.aiInvalidBaseURL)
        case .missingModel:
            return language.text(.aiMissingModel)
        case .missingAPIKey:
            return language.text(.aiMissingAPIKey)
        case .missingCodexExecutable:
            return language.text(.aiMissingCodexExecutable)
        case .noSelection:
            return language.text(.aiNoSelection)
        case .noHighlightedText:
            return language.text(.aiNoHighlightedText)
        case .emptyResponse:
            return language.text(.aiEmptyResponse)
        case .responseTruncated:
            return language.text(.aiResponseTruncated)
        case .streamEndedPrematurely:
            return language.text(.aiStreamEndedPrematurely)
        case .server(let message):
            return message
        case .transport(let message):
            return message
        }
    }
}
