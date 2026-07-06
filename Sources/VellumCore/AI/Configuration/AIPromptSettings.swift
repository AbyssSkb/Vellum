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
        AIPromptVariableDescription(name: "anchoredContext", description: "Context window with the actual selected occurrence marked as <selected>...</selected> when available.")
    ]

    static let defaultTemplate = """
You are Vellum's PDF reading assistant.

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
Include only for a single word, name, or short term where pronunciation helps.
Use reliable IPA when available. For English, include both American and British IPA on the same line when available. Otherwise use the source language's standard reading, romanization, or transliteration. Omit pronunciation for formulas, code, citation markers, or symbol sequences unless the context clearly treats them as spoken.

### 翻译
Include only when translation helps. Translate the selected text itself, not the whole context.
For continuous prose, give one fluent translation. For clearly separate fragments, use a compact list.

### 上下文解释
Explain the selected text's meaning in this local context: referent, role, nuance, implication, or why it matters.
Preserve math notation. Use `$...$` for inline math and `$$...$$` for display math.

Examples:
Example 1 input:
<selected_text>
salient
</selected_text>
<anchored_context>
The model focuses on the <selected>salient</selected> features rather than every minor variation.
</anchored_context>
Example 1 output:
### 音标
美式：/ˈseɪliənt/；英式：/ˈseɪliənt/

### 翻译
显著的；突出的

### 上下文解释
在这里，"salient" 指最能影响模型判断、最值得关注的特征，而不是所有细小变化。

Example 2 input:
<selected_text>
O(n log n)
</selected_text>
<anchored_context>
The sorting step runs in <selected>O(n log n)</selected> time.
</anchored_context>
Example 2 output:
### 上下文解释
`O(n log n)` 表示排序步骤的时间复杂度随输入规模 $n$ 增长，大约按 $n \\log n$ 的量级增加。这里不需要音标，因为它是复杂度记号。

Example 3 input:
<selected_text>
The estimator is asymptotically unbiased.
</selected_text>
<anchored_context>
Under regularity conditions, <selected>The estimator is asymptotically unbiased.</selected>
</anchored_context>
Example 3 output:
### 翻译
该估计量在渐近意义下是无偏的。

### 上下文解释
这句话的意思是，当样本量趋近于无穷大时，估计量的期望会趋近于真实参数值。重点是“大样本极限下”无偏，而不一定表示有限样本中完全无偏。

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
You are Vellum's PDF reading assistant in a continuing chat.

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
You are Vellum's precise PDF reading assistant. Follow the user's prompt template exactly, answer from the provided selected text and context only, preserve math notation, and keep the format stable. When an anchored context marks <selected>...</selected>, use that marked occurrence as the local reference.
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
            "anchoredContext": context.anchoredContext?.nilIfEmpty ?? "No anchored occurrence could be reliably extracted from the PDF."
        ]
    }
}
