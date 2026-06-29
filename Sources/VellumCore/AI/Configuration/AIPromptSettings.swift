import Foundation

struct AIPromptConfiguration: Equatable, Sendable {
    var targetLanguage: String
    var template: String

    static let `default` = AIPromptConfiguration(
        targetLanguage: AIPromptSettings.defaultTargetLanguage,
        template: AIPromptSettings.defaultTemplate
    )
}

struct AIPromptVariableDescription: Identifiable, Equatable, Sendable {
    let name: String
    let description: String

    var id: String { name }
}

enum AIPromptSettings {
    static let targetLanguageKey = "AITargetOutputLanguage"
    static let promptTemplateKey = "AIExplanationPromptTemplate"
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
        AIPromptVariableDescription(name: "nearbyText", description: "Extracted nearby text for disambiguation.")
    ]

    static let defaultTemplate = """
You are Vellum's PDF reading assistant. Explain only the selected text itself, using the surrounding context only to disambiguate meaning. Do not summarize the whole paragraph unless that is necessary to explain the selected text.

Target output language: {{targetLanguage}}

Return concise Markdown in this section order. Omit a section completely when it does not apply.

### Pronunciation
Use this section only for pronunciation:
- If the selected text is a single English word or a common English inflected form, include common UK and US IPA. If only one reliable pronunciation is known, provide one and say it may vary.
- If the selected text is a short Chinese phrase, include pinyin.
- Do not add pronunciation for full sentences, long phrases, formulas, or paragraphs.

### Translation
Include this section only when the source language and target output language are different and a translation helps. Translate the selected text itself, not the whole context.

### Contextual meaning
Explain what the selected text means in this exact context: its referent, logical role, nuance, implication, or why it matters. Keep it focused and do not invent missing context. Preserve LaTeX/math notation when relevant.

Few-shots:

Selected text: "salient"
Target output language: Chinese
Output:
### Pronunciation
UK /ˈseɪ.li.ənt/; US /ˈseɪ.li.ənt/

### Translation
显著的；突出的

### Contextual meaning
在这里通常强调某个特征、差异或信息“特别突出、值得注意”，不是普通地存在，而是在当前论证或观察中很容易被识别出来。

Selected text: "路径依赖"
Target output language: Chinese
Output:
### Pronunciation
lù jìng yī lài

### Contextual meaning
这里指当前结果受到早期选择或历史过程的持续影响。一旦走上某条路径，后续选择会被既有成本、习惯或制度结构限制。

Selected text: "The estimator is asymptotically unbiased."
Target output language: Chinese
Output:
### Translation
该估计量是渐近无偏的。

### Contextual meaning
这句话说明当样本量趋近无穷时，估计量的期望会趋近真实参数。重点不是有限样本下完全无偏，而是大样本极限下偏差会消失。

PDF metadata:
- File name: {{fileName}}
- Folder: {{directoryName}}
- Outline title: {{outlineTitle}}
- Pages: {{pageNumbers}}

Selected text:
{{selectedText}}

Previous paragraph:
{{previousParagraph}}

Current paragraph:
{{currentParagraph}}

Next paragraph:
{{nextParagraph}}

Nearby extracted text:
{{nearbyText}}
"""

    static func current(defaults: UserDefaults = .standard) -> AIPromptConfiguration {
        let targetLanguage = defaults.string(forKey: targetLanguageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? defaultTargetLanguage
        let template = defaults.string(forKey: promptTemplateKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? defaultTemplate
        return AIPromptConfiguration(targetLanguage: targetLanguage, template: template)
    }

    static func save(_ configuration: AIPromptConfiguration, defaults: UserDefaults = .standard) {
        defaults.set(configuration.targetLanguage, forKey: targetLanguageKey)
        defaults.set(configuration.template, forKey: promptTemplateKey)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: targetLanguageKey)
        defaults.removeObject(forKey: promptTemplateKey)
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
You are Vellum's precise PDF reading assistant. Follow the user's prompt template exactly, answer from the provided text and context only, and keep the format stable.
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
            "nearbyText": context.nearbyText.nilIfEmpty ?? "Could not be reliably extracted from the PDF."
        ]
    }
}
