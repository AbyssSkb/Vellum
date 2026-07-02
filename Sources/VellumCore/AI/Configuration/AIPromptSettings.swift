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
        AIPromptVariableDescription(name: "fileName", description: "Current PDF file name."),
        AIPromptVariableDescription(name: "directoryName", description: "Parent folder name when available."),
        AIPromptVariableDescription(name: "outlineTitle", description: "Nearest PDF outline title when available."),
        AIPromptVariableDescription(name: "pageNumbers", description: "Pages covered by the selection."),
        AIPromptVariableDescription(name: "previousParagraph", description: "Paragraph before the selected text."),
        AIPromptVariableDescription(name: "currentParagraph", description: "Paragraph containing the selected text."),
        AIPromptVariableDescription(name: "nextParagraph", description: "Paragraph after the selected text."),
        AIPromptVariableDescription(name: "nearbyText", description: "Extracted nearby text for disambiguation."),
        AIPromptVariableDescription(name: "selectionKind", description: "Automatic structural classification of the selected text."),
        AIPromptVariableDescription(name: "pronunciationGuidance", description: "Generic pronunciation policy for this selection.")
    ]

    static let defaultTemplate = """
You are Vellum's PDF reading assistant. Explain the complete selected text itself, using the surrounding context only to disambiguate meaning. Do not summarize the whole paragraph unless that is necessary to explain the selected text.

The selected text may contain PDF line wraps, multiple paragraphs, or several non-contiguous fragments copied from different places in the PDF. Treat everything inside Selected text as the user's target. Cover the complete selection in its original order. Do not answer only the first sentence, first line, most familiar phrase, or one representative fragment. If the selection is continuous prose broken only by PDF line wrapping, treat it as one passage rather than separate fragments. If it truly contains separate non-contiguous fragments, cover each fragment and briefly explain how they relate when useful.

Target output language: {{targetLanguage}}

Return concise Markdown in this section order, but write the section headings in the target output language. For Chinese output, use "### 音标", "### 翻译", and "### 上下文解释". Omit a section completely when it does not apply.

Selection kind: {{selectionKind}}
Pronunciation requirement: {{pronunciationGuidance}}

Pronunciation section:
Use this section only for pronunciation:
- Follow the pronunciation requirement near the selected text.
- For a single natural-language word, name, or term in any source language, include the pronunciation section. Do not omit it.
- Prefer standard IPA when reliable. If IPA is not reliable or not the most useful reading aid, use the source language's standard reading or romanization, such as pinyin for Chinese, kana or romaji for Japanese, romanization for Korean, or a standard transliteration for other scripts.
- If the selected text is an acronym, formula, code, citation marker, or symbol sequence, omit pronunciation unless the context clearly treats it as a spoken term.
- Do not add pronunciation for full sentences, long phrases, formulas, or paragraphs.

Translation section:
Include this section only when the source language and target output language are different and a translation helps. Translate the selected text itself, not the whole context. If the selected text is a continuous phrase, sentence, or paragraph, write one fluent translation that preserves the original sentence flow; do not split it into a numbered list merely because the PDF text wrapped across lines. Use a compact numbered or bulleted list only when the selected text clearly contains separate list items or non-contiguous fragments. Do not omit difficult, repeated, formula-adjacent, or later fragments.

Contextual meaning section:
Explain what the selected text means in this exact context: its referent, logical role, nuance, implication, or why it matters. For multi-fragment selections, explain each fragment and the local role it plays before synthesizing. Keep it focused and do not invent missing context. Preserve LaTeX/math notation when relevant.

Few-shots:

Selected text: "salient"
Target output language: Chinese
Output:
### 音标
UK /ˈseɪ.li.ənt/; US /ˈseɪ.li.ənt/

### 翻译
显著的；突出的

### 上下文解释
在这里通常强调某个特征、差异或信息“特别突出、值得注意”，不是普通地存在，而是在当前论证或观察中很容易被识别出来。

Selected text: "路径依赖"
Target output language: Chinese
Output:
### 音标
lù jìng yī lài

### 上下文解释
这里指当前结果受到早期选择或历史过程的持续影响。一旦走上某条路径，后续选择会被既有成本、习惯或制度结构限制。

Selected text: "The estimator is asymptotically unbiased."
Target output language: Chinese
Output:
### 翻译
该估计量是渐近无偏的。

### 上下文解释
这句话说明当样本量趋近无穷时，估计量的期望会趋近真实参数。重点不是有限样本下完全无偏，而是大样本极限下偏差会消失。

PDF metadata:
- File name: {{fileName}}
- Folder: {{directoryName}}
- Outline title: {{outlineTitle}}
- Pages: {{pageNumbers}}

Selected text:
{{selectedText}}

Coverage reminder:
Before finalizing, verify that every line, paragraph, and non-contiguous fragment in Selected text has been addressed. If a fragment is unclear because the PDF extraction is noisy, mention that fragment briefly instead of silently skipping it.

Selection kind:
{{selectionKind}}

Pronunciation requirement:
{{pronunciationGuidance}}

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
You are Vellum's PDF reading assistant. The user selected text in a PDF and wants to discuss it through a continuing chat.

Target output language: {{targetLanguage}}

Use the complete selected text and context window below as the shared reference for the whole conversation. The selected text may contain multiple lines, multiple paragraphs, or several non-contiguous fragments copied from different places in the PDF. Treat every fragment inside Selected text as part of the user's target.

Answer the user's latest message directly. Keep answers focused on the selected passage unless the user asks to compare, translate, simplify, or connect it to the surrounding paragraph. If the user asks to translate, explain, summarize, compare, or restate "the selected text", cover all selected fragments in their original order; do not answer only the first fragment or a representative fragment. If the question needs information not present in the context, say what is missing instead of inventing details.

PDF metadata:
- File name: {{fileName}}
- Folder: {{directoryName}}
- Outline title: {{outlineTitle}}
- Pages: {{pageNumbers}}

Selected text:
{{selectedText}}

Coverage reminder:
When the user's request concerns the selected text as a whole, verify that every selected line, paragraph, and non-contiguous fragment has been addressed.

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
You are Vellum's precise PDF reading assistant. Follow the user's prompt template exactly, answer from the provided text and context only, and keep the format stable. If the user prompt marks pronunciation as required, include that section. If the selected text contains multiple lines, paragraphs, or non-contiguous fragments, cover every selected fragment in order and do not silently skip later fragments.
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
            "previousParagraph": context.previousParagraph?.nilIfEmpty ?? "Could not be reliably extracted from the PDF.",
            "currentParagraph": context.currentParagraph?.nilIfEmpty ?? "Could not be reliably extracted from the PDF.",
            "nextParagraph": context.nextParagraph?.nilIfEmpty ?? "Could not be reliably extracted from the PDF.",
            "nearbyText": context.nearbyText.nilIfEmpty ?? "Could not be reliably extracted from the PDF.",
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
