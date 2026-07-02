import Foundation

struct AIExplanationContext: Sendable {
    var selectedText: String
    var previousParagraph: String?
    var currentParagraph: String?
    var nextParagraph: String?
    var nearbyText: String
    var fileName: String
    var documentKey: String? = nil
    var directoryName: String?
    var outlineTitle: String?
    var pageNumbers: [Int]

    var prompt: String {
        AIPromptRenderer.renderUserPrompt(context: self)
    }
}
