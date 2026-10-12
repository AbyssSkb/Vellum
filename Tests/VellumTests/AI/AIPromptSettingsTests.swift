import Foundation
import Testing
@testable import VellumCore

@Suite("AI prompt settings")
struct AIPromptSettingsTests {
    @Test
    func insertedContextIsNeverReinterpretedAsTemplateVariables() {
        let context = AIExplanationContext(
            selectedText: "literal {{targetLanguage}} and {{fileName}} 🐈",
            currentParagraph: "{{selectedText}}",
            nearbyText: "{{currentParagraph}}",
            fileName: "{{targetLanguage}}.pdf",
            pageNumbers: [1]
        )
        let configuration = AIPromptConfiguration(
            targetLanguage: "{{selectedText}}",
            template: "{{selectedText}}|{{targetLanguage}}|{{fileName}}|{{currentParagraph}}|{{nearbyText}}|{{unknown}}"
        )

        #expect(AIPromptRenderer.renderUserPrompt(context: context, configuration: configuration)
            == "literal {{targetLanguage}} and {{fileName}} 🐈|{{selectedText}}|{{targetLanguage}}.pdf|{{selectedText}}|{{currentParagraph}}|{{unknown}}")
    }

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
            pageNumbers: [2, 3],
            anchoredContext: "The <selected>salient</selected> factor matters."
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
            Anchored={{anchoredContext}}
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
        #expect(prompt.contains("Anchored=The <selected>salient</selected> factor matters."))
        #expect(!prompt.contains("{{"))
    }

    @Test
    func defaultPromptPreservesSelectionAndMissingAnchoredContext() {
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

        #expect(prompt.contains("<selected_text>\nsalient\n</selected_text>"))
        #expect(prompt.contains("<anchored_context>\nNo anchored occurrence could be reliably extracted from the PDF.\n</anchored_context>"))
    }

    @Test
    func currentSettingsFallBackToDefaultPrompt() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults

        let configuration = AIPromptSettings.current(defaults: defaults)

        #expect(configuration.targetLanguage == AIPromptSettings.defaultTargetLanguage)
        #expect(configuration.template == AIPromptSettings.defaultTemplate)
    }

    @Test
    func saveAndResetPromptSettings() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults

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
    func conversationPromptSettingsAreIndependentFromExplanationPromptSettings() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults

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
    func defaultPromptPreservesCompleteSelectionAndAnchoredOccurrence() {
        let context = AIExplanationContext(
            selectedText: "First selected sentence.\n\nSecond selected sentence.",
            previousParagraph: "Before",
            currentParagraph: "First selected sentence. Other text. Second selected sentence.",
            nextParagraph: "After",
            nearbyText: "Nearby",
            fileName: "paper.pdf",
            directoryName: nil,
            outlineTitle: nil,
            pageNumbers: [1, 4],
            anchoredContext: "Before\n<selected>First selected sentence.</selected>\nOther text\n<selected>Second selected sentence.</selected>\nAfter"
        )

        let prompt = AIPromptRenderer.render(context: context).combined

        #expect(prompt.contains("<selected_text>\nFirst selected sentence.\n\nSecond selected sentence.\n</selected_text>"))
        #expect(prompt.contains("<selected>First selected sentence.</selected>"))
    }

    @Test
    func defaultConversationPromptPreservesCompleteSelection() {
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

        #expect(prompt.contains("<selected_text>\nFirst claim.\nSecond claim.\n</selected_text>"))
    }
}
