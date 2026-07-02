import Foundation
import Testing
@testable import VellumCore

@Suite("AI prompt settings")
struct AIPromptSettingsTests {
    @Test
    func rendererSubstitutesContextVariablesAndTargetLanguage() {
        let context = AIExplanationContext(
            selectedText: "salient",
            previousParagraph: "Before",
            currentParagraph: "The salient factor matters.",
            nextParagraph: "After",
            nearbyText: "Nearby context",
            fileName: "paper.pdf",
            directoryName: "Reading",
            outlineTitle: "Methods",
            pageNumbers: [2, 3]
        )
        let configuration = AIPromptConfiguration(
            targetLanguage: "Japanese",
            template: """
            Language={{targetLanguage}}
            Text={{selectedText}}
            File={{fileName}}
            Folder={{directoryName}}
            Outline={{outlineTitle}}
            Pages={{pageNumbers}}
            Previous={{previousParagraph}}
            Current={{currentParagraph}}
            Next={{nextParagraph}}
            Nearby={{nearbyText}}
            """
        )

        let prompt = AIPromptRenderer.renderUserPrompt(context: context, configuration: configuration)

        #expect(prompt.contains("Language=Japanese"))
        #expect(prompt.contains("Text=salient"))
        #expect(prompt.contains("File=paper.pdf"))
        #expect(prompt.contains("Folder=Reading"))
        #expect(prompt.contains("Outline=Methods"))
        #expect(prompt.contains("Pages=2, 3"))
        #expect(prompt.contains("Previous=Before"))
        #expect(prompt.contains("Current=The salient factor matters."))
        #expect(prompt.contains("Next=After"))
        #expect(prompt.contains("Nearby=Nearby context"))
        #expect(!prompt.contains("{{"))
    }

    @Test
    func rendererAddsPronunciationGuidanceForSingleToken() {
        let context = AIExplanationContext(
            selectedText: "salient",
            previousParagraph: nil,
            currentParagraph: "The salient factor matters.",
            nextParagraph: nil,
            nearbyText: "",
            fileName: "paper.pdf",
            directoryName: nil,
            outlineTitle: nil,
            pageNumbers: [2]
        )

        let prompt = AIPromptRenderer.renderUserPrompt(context: context, configuration: .default)

        #expect(prompt.contains("Selection kind: single token or compact term"))
        #expect(prompt.contains("Pronunciation requirement: Expected: if this is a natural-language word, name, or term in any source language"))
        #expect(prompt.contains("Selected text:\nsalient"))
        #expect(prompt.contains("Selection kind:\nsingle token or compact term"))
        #expect(prompt.contains("Pronunciation requirement:\nExpected: if this is a natural-language word"))
        #expect(prompt.contains("For a single natural-language word, name, or term in any source language, include the pronunciation section. Do not omit it."))
    }

    @Test
    func rendererUsesSameSingleTokenGuidanceAcrossLanguages() {
        let englishGuidance = AIPromptRenderer.pronunciationGuidance(for: "salient")
        let chineseGuidance = AIPromptRenderer.pronunciationGuidance(for: "路径依赖")
        let japaneseGuidance = AIPromptRenderer.pronunciationGuidance(for: "改善")

        #expect(englishGuidance == chineseGuidance)
        #expect(chineseGuidance == japaneseGuidance)
        #expect(englishGuidance.contains("any source language"))
    }

    @Test
    func rendererDoesNotRequirePronunciationForSentence() {
        let guidance = AIPromptRenderer.pronunciationGuidance(for: "The estimator is asymptotically unbiased.")

        #expect(guidance == "Not required: omit pronunciation unless it is clearly useful and reliable.")
    }

    @Test
    func rendererEncouragesPronunciationForShortPhrase() {
        let guidance = AIPromptRenderer.pronunciationGuidance(for: "laissez faire")

        #expect(guidance.contains("Optional but encouraged"))
        #expect(guidance.contains("romanization, or transliteration"))
    }

    @Test
    func currentSettingsFallBackToDefaultPrompt() {
        let suiteName = "AIPromptSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let configuration = AIPromptSettings.current(defaults: defaults)

        #expect(configuration.targetLanguage == AIPromptSettings.defaultTargetLanguage)
        #expect(configuration.template == AIPromptSettings.defaultTemplate)
        #expect(configuration.template.contains("Target output language: {{targetLanguage}}"))
        #expect(configuration.template.contains("Few-shots:"))
        #expect(configuration.template.contains("### 音标"))
        #expect(configuration.template.contains("### 翻译"))
        #expect(configuration.template.contains("### 上下文解释"))
        #expect(configuration.template.contains("Cover every selected fragment in its original order."))
        #expect(configuration.template.contains("verify that every line, paragraph, and non-contiguous fragment"))
        #expect(!configuration.template.contains("### Pronunciation"))
    }

    @Test
    func saveAndResetPromptSettings() {
        let suiteName = "AIPromptSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        AIPromptSettings.save(
            AIPromptConfiguration(targetLanguage: "Korean", template: "Explain {{selectedText}}."),
            defaults: defaults
        )
        #expect(AIPromptSettings.current(defaults: defaults).targetLanguage == "Korean")
        #expect(AIPromptSettings.current(defaults: defaults).template == "Explain {{selectedText}}.")

        AIPromptSettings.reset(defaults: defaults)
        #expect(AIPromptSettings.current(defaults: defaults) == .default)
    }

    @Test
    func conversationPromptSettingsAreIndependentFromExplanationPromptSettings() {
        let suiteName = "AIPromptSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        AIPromptSettings.save(
            AIPromptConfiguration(targetLanguage: "Japanese", template: "Explain {{selectedText}}."),
            profile: .explanation,
            defaults: defaults
        )
        AIPromptSettings.save(
            AIPromptConfiguration(targetLanguage: "Korean", template: "Chat about {{selectedText}} in {{targetLanguage}}."),
            profile: .conversation,
            defaults: defaults
        )

        #expect(AIPromptSettings.current(profile: .explanation, defaults: defaults).targetLanguage == "Japanese")
        #expect(AIPromptSettings.current(profile: .explanation, defaults: defaults).template == "Explain {{selectedText}}.")
        #expect(AIPromptSettings.current(profile: .conversation, defaults: defaults).targetLanguage == "Korean")
        #expect(AIPromptSettings.current(profile: .conversation, defaults: defaults).template == "Chat about {{selectedText}} in {{targetLanguage}}.")

        AIPromptSettings.reset(profile: .conversation, defaults: defaults)
        #expect(AIPromptSettings.current(profile: .explanation, defaults: defaults).template == "Explain {{selectedText}}.")
        #expect(AIPromptSettings.current(profile: .conversation, defaults: defaults) == .defaultConversation)
    }

    @Test
    func conversationPromptRendererUsesConfiguredTemplate() {
        let context = AIExplanationContext(
            selectedText: "term",
            previousParagraph: "Before",
            currentParagraph: "Current term.",
            nextParagraph: "After",
            nearbyText: "Nearby",
            fileName: "paper.pdf",
            directoryName: "Reading",
            outlineTitle: "Intro",
            pageNumbers: [4]
        )
        let configuration = AIPromptConfiguration(
            targetLanguage: "Chinese",
            template: "Discuss {{selectedText}} from {{fileName}} on {{pageNumbers}} in {{targetLanguage}}."
        )

        let prompt = AIConversationPromptRenderer.systemPrompt(
            context: context,
            configuration: configuration
        )

        #expect(prompt == "Discuss term from paper.pdf on 4 in Chinese.")
    }

    @Test
    func defaultPromptEmphasizesCompleteMultiFragmentCoverage() {
        let context = AIExplanationContext(
            selectedText: "First selected sentence.\n\nSecond selected sentence.",
            previousParagraph: "Before",
            currentParagraph: "First selected sentence. Other text. Second selected sentence.",
            nextParagraph: "After",
            nearbyText: "Nearby",
            fileName: "paper.pdf",
            directoryName: nil,
            outlineTitle: nil,
            pageNumbers: [1, 4]
        )

        let prompt = AIPromptRenderer.render(context: context).combined

        #expect(prompt.contains("Cover every selected fragment in its original order."))
        #expect(prompt.contains("If the selected text contains multiple fragments, translate all fragments in order."))
        #expect(prompt.contains("Before finalizing, verify that every line, paragraph, and non-contiguous fragment"))
        #expect(prompt.contains("First selected sentence.\n\nSecond selected sentence."))
    }

    @Test
    func defaultConversationPromptEmphasizesCompleteSelectionCoverage() {
        let context = AIExplanationContext(
            selectedText: "First claim.\nSecond claim.",
            currentParagraph: "First claim. Second claim.",
            nearbyText: "Nearby",
            fileName: "paper.pdf",
            pageNumbers: [5]
        )

        let prompt = AIConversationPromptRenderer.systemPrompt(
            context: context,
            configuration: .defaultConversation
        )

        #expect(prompt.contains("Treat every fragment inside Selected text as part of the user's target."))
        #expect(prompt.contains("cover all selected fragments in their original order"))
        #expect(prompt.contains("verify that every selected line, paragraph, and non-contiguous fragment"))
    }
}
