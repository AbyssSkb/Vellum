import Foundation

struct AIPromptConfiguration: Equatable, Sendable {
    var targetLanguage: String
    var template: String

    static let `default` = AIPromptConfiguration(
        targetLanguage: AIPromptSettings.defaultTargetLanguage,
        template: AIPromptSettings.defaultTemplate
    )

    static let defaultConversation = AIPromptConfiguration(
        targetLanguage: AIPromptSettings.defaultTargetLanguage,
        template: AIPromptSettings.defaultConversationTemplate
    )
}

struct AIPromptVariableDescription: Identifiable, Equatable, Sendable {
    let name: String
    let description: String

    var id: String { name }
}

enum AIPromptProfile: Sendable {
    case explanation
    case conversation

    var targetLanguageKey: String {
        switch self {
        case .explanation:
            return AIPromptSettings.targetLanguageKey
        case .conversation:
            return AIPromptSettings.conversationTargetLanguageKey
        }
    }

    var promptTemplateKey: String {
        switch self {
        case .explanation:
            return AIPromptSettings.promptTemplateKey
        case .conversation:
            return AIPromptSettings.conversationPromptTemplateKey
        }
    }

    var defaultTemplate: String {
        switch self {
        case .explanation:
            return AIPromptSettings.defaultTemplate
        case .conversation:
            return AIPromptSettings.defaultConversationTemplate
        }
    }
}

enum AIPromptSettings {
    static let targetLanguageKey = "AITargetOutputLanguage"
    static let promptTemplateKey = "AIExplanationPromptTemplate"
    static let conversationTargetLanguageKey = "AIConversationTargetOutputLanguage"
    static let conversationPromptTemplateKey = "AIConversationPromptTemplate"
    static let defaultTargetLanguage = "Chinese"

    static let variableDescriptions: [AIPromptVariableDescription] = [
        AIPromptVariableDescription(name: "targetLanguage", description: "Target output language from Settings."),
        AIPromptVariableDescription(name: "selectedText", description: "The exact highlighted text."),
        AIPromptVariableDescription(name: "fileName", description: "Current document file name."),
        AIPromptVariableDescription(name: "directoryName", description: "Parent folder name when available."),
        AIPromptVariableDescription(name: "outlineTitle", description: "Nearest document outline title when available."),
        AIPromptVariableDescription(name: "pageNumbers", description: "Pages covered by the selection."),
        AIPromptVariableDescription(name: "previousParagraph", description: "Paragraph before the selected text."),
        AIPromptVariableDescription(name: "currentParagraph", description: "Paragraph containing the selected text."),
        AIPromptVariableDescription(name: "nextParagraph", description: "Paragraph after the selected text."),
        AIPromptVariableDescription(name: "nearbyText", description: "Extracted nearby text for disambiguation."),
        AIPromptVariableDescription(name: "anchoredContext", description: "Context window with the actual selected occurrence marked as <selected>...</selected> when available."),
        AIPromptVariableDescription(name: "selectionKind", description: "Automatic structural classification of the selected text."),
        AIPromptVariableDescription(name: "pronunciationGuidance", description: "Generic pronunciation policy for this selection.")
    ]

    static let defaultTemplate = """
You are Vellum's document reading assistant.

Answer in {{targetLanguage}}. Use concise Markdown. Do not add a preface.

Task:
Explain the selected text itself. Use context only to disambiguate the selected text, not to summarize the surrounding paragraph.

Selection policy:
- Treat everything inside <selected_text> as the user's target.
- Cover the complete selected text in its original order.
- If the selected text contains multiple fragments, explain each relevant fragment briefly before synthesizing.
- If <anchored_context> contains <selected>...</selected> and the same text appears multiple times, use only the marked occurrence.
- If no marked occurrence is available and the context is ambiguous, say the exact occurrence is ambiguous instead of guessing.

Output format:
Use only the sections that apply. Write section headings in {{targetLanguage}}. For Chinese output, use "### 音标", "### 翻译", and "### 上下文解释".

### 音标
Include only for a single word, name, short term, or short phrase where pronunciation helps.
Policy: {{pronunciationGuidance}}

### 翻译
Include only when translation helps. Translate the selected text itself, not the whole context.
For continuous prose, give one fluent translation. For clearly separate fragments, use a compact list.

### 上下文解释
Explain the selected text's meaning in this local context: referent, role, nuance, implication, or why it matters.
Preserve math notation. Use `$...$` for inline math and `$$...$$` for display math.

Metadata:
- File: {{fileName}}
- Folder: {{directoryName}}
- Outline: {{outlineTitle}}
- Pages: {{pageNumbers}}
- Selection kind: {{selectionKind}}

<selected_text>
{{selectedText}}
</selected_text>

<anchored_context>
{{anchoredContext}}
</anchored_context>

Fallback context if no anchored context is available:
Previous paragraph:
{{previousParagraph}}

Current paragraph:
{{currentParagraph}}

Next paragraph:
{{nextParagraph}}

Nearby extracted text:
{{nearbyText}}
"""

    static let defaultConversationTemplate = """
You are Vellum's document reading assistant in a continuing chat.

Answer in {{targetLanguage}}. Use Markdown. Be direct and focused.

Shared reference:
The user selected the text inside <selected_text>. Use it as the main object of discussion.

Rules:
- Answer the user's latest message directly.
- If the user says "this", "it", "the passage", or "the selected text", refer to the complete selected text.
- If the selected text contains multiple fragments, cover all relevant fragments in order.
- If <anchored_context> contains <selected>...</selected> and the same text appears multiple times, use only the marked occurrence.
- If the user asks for information not available in the selected text or context, say what is missing.
- Preserve math notation. Use `$...$` for inline math and `$$...$$` for display math.
- Do not repeat metadata unless it helps answer the question.

Metadata:
- File: {{fileName}}
- Folder: {{directoryName}}
- Outline: {{outlineTitle}}
- Pages: {{pageNumbers}}

<selected_text>
{{selectedText}}
</selected_text>

<anchored_context>
{{anchoredContext}}
</anchored_context>

Fallback context:
Previous paragraph:
{{previousParagraph}}

Current paragraph:
{{currentParagraph}}

Next paragraph:
{{nextParagraph}}

Nearby extracted text:
{{nearbyText}}
"""

    static func current(
        profile: AIPromptProfile = .explanation,
        defaults: UserDefaults = .standard
    ) -> AIPromptConfiguration {
        let targetLanguage = defaults.string(forKey: profile.targetLanguageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? defaultTargetLanguage
        let storedTemplate = defaults.string(forKey: profile.promptTemplateKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let template = storedTemplate ?? profile.defaultTemplate
        return AIPromptConfiguration(targetLanguage: targetLanguage, template: template)
    }

    static func save(
        _ configuration: AIPromptConfiguration,
        profile: AIPromptProfile = .explanation,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(configuration.targetLanguage, forKey: profile.targetLanguageKey)
        defaults.set(configuration.template, forKey: profile.promptTemplateKey)
    }

    static func reset(
        profile: AIPromptProfile = .explanation,
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: profile.targetLanguageKey)
        defaults.removeObject(forKey: profile.promptTemplateKey)
    }

}

struct AIRenderedPrompt: Equatable, Sendable {
    var system: String
    var user: String

    var combined: String {
        "\(system)\n\n\(user)"
    }
}

enum AIPromptRenderer {
    static let systemPrompt = """
You are Vellum's precise document reading assistant. Follow the user's prompt template exactly, answer from the provided selected text and context only, preserve math notation, and keep the format stable. When an anchored context marks <selected>...</selected>, use that marked occurrence as the local reference.
"""

    static func render(
        context: AIExplanationContext,
        configuration: AIPromptConfiguration = AIPromptSettings.current()
    ) -> AIRenderedPrompt {
        AIRenderedPrompt(
            system: systemPrompt,
            user: renderUserPrompt(context: context, configuration: configuration)
        )
    }

    static func renderUserPrompt(
        context: AIExplanationContext,
        configuration: AIPromptConfiguration = AIPromptSettings.current()
    ) -> String {
        var prompt = configuration.template
        for (name, value) in variables(context: context, configuration: configuration) {
            prompt = prompt.replacingOccurrences(of: "{{\(name)}}", with: value)
        }
        return prompt
    }

    static func variables(
        context: AIExplanationContext,
        configuration: AIPromptConfiguration
    ) -> [String: String] {
        [
            "targetLanguage": configuration.targetLanguage,
            "selectedText": context.selectedText,
            "fileName": context.fileName,
            "directoryName": context.directoryName?.nilIfEmpty ?? "Unknown",
            "outlineTitle": context.outlineTitle?.nilIfEmpty ?? "Unknown",
            "pageNumbers": context.pageNumbers.map(String.init).joined(separator: ", "),
            "previousParagraph": context.previousParagraph?.nilIfEmpty ?? "Could not be reliably extracted from the document.",
            "currentParagraph": context.currentParagraph?.nilIfEmpty ?? "Could not be reliably extracted from the document.",
            "nextParagraph": context.nextParagraph?.nilIfEmpty ?? "Could not be reliably extracted from the document.",
            "nearbyText": context.nearbyText.nilIfEmpty ?? "Could not be reliably extracted from the document.",
            "anchoredContext": context.anchoredContext?.nilIfEmpty ?? "No anchored occurrence could be reliably extracted from the document.",
            "selectionKind": selectionKindDescription(for: context.selectedText),
            "pronunciationGuidance": pronunciationGuidance(for: context.selectedText)
        ]
    }

    static func selectionKindDescription(for selectedText: String) -> String {
        let kind = selectionKind(for: selectedText)
        switch kind {
        case .singleToken:
            return "single token or compact term"
        case .shortPhrase:
            return "short phrase"
        case .other:
            return "sentence, long phrase, formula, paragraph, or unknown"
        }
    }

    static func pronunciationGuidance(for selectedText: String) -> String {
        let kind = selectionKind(for: selectedText)
        switch kind {
        case .singleToken:
            return "Expected: if this is a natural-language word, name, or term in any source language, include a pronunciation section. Use reliable IPA when available; otherwise use the source language's standard reading, romanization, or transliteration. If it is an acronym, formula, code, citation marker, or symbol sequence, omit pronunciation unless the context clearly treats it as spoken."
        case .shortPhrase:
            return "Optional but encouraged: include pronunciation, reading, romanization, or transliteration when it helps read or disambiguate this short phrase. Omit it for formulas, citations, code, or phrases where pronunciation is not useful."
        case .other:
            return "Not required: omit pronunciation unless it is clearly useful and reliable."
        }
    }

    private static func selectionKind(for selectedText: String) -> SelectionKind {
        let whitespaceTrimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasWhitespace = whitespaceTrimmed.contains { $0.isWhitespace || $0.isNewline }
        guard !whitespaceTrimmed.isEmpty,
              !(hasWhitespace && containsHardSentenceBoundary(whitespaceTrimmed)) else {
            return .other
        }

        let trimmed = whitespaceTrimmed
            .trimmingCharacters(in: .punctuationCharacters)
        guard !trimmed.isEmpty else {
            return .other
        }

        if !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }) {
            return .singleToken
        }

        let tokens = trimmed
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        if (2...5).contains(tokens.count), trimmed.count <= 48 {
            return .shortPhrase
        }
        return .other
    }

    private static func containsHardSentenceBoundary(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x000A, 0x000D, 0x002E, 0x003F, 0x0021, 0x003B, 0x3002, 0xFF1F, 0xFF01, 0xFF1B:
                return true
            default:
                return false
            }
        }
    }
}

private enum SelectionKind {
    case singleToken
    case shortPhrase
    case other
}
