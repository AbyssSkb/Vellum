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
    func defaultPromptKeepsPronunciationInstructionNonDynamic() {
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

        #expect(prompt.contains("Use reliable IPA when available"))
        #expect(prompt.contains("For English, include both American and British IPA on the same line when available."))
        #expect(prompt.contains("Examples:"))
        #expect(prompt.contains("Example 1 input:"))
        #expect(prompt.contains("美式：/ˈseɪliənt/；英式：/ˈseɪliənt/"))
        #expect(prompt.contains("Example 2 output:\n### 上下文解释"))
        #expect(prompt.contains("这里不需要音标，因为它是复杂度记号。"))
        #expect(prompt.contains("<selected_text>\nsalient\n</selected_text>"))
        #expect(prompt.contains("<anchored_context>\nNo anchored occurrence could be reliably extracted from the PDF.\n</anchored_context>"))
        #expect(prompt.contains("Include only for a single word, name, or short term where pronunciation helps."))
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
        #expect(configuration.template.contains("Answer in {{targetLanguage}}. Use concise Markdown."))
        #expect(configuration.template.contains("### 音标"))
        #expect(configuration.template.contains("### 翻译"))
        #expect(configuration.template.contains("### 上下文解释"))
        #expect(configuration.template.contains("Examples:"))
        #expect(configuration.template.contains("Example 3 output:"))
        #expect(configuration.template.contains("<selected_text>"))
        #expect(configuration.template.contains("<anchored_context>"))
        #expect(configuration.template.contains("Use `$...$` for inline math and `$$...$$` for display math."))
        #expect(!configuration.template.contains("Few-shots:"))
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
            pageNumbers: [1, 4],
            anchoredContext: "Before\n<selected>First selected sentence.</selected>\nOther text\n<selected>Second selected sentence.</selected>\nAfter"
        )

        let prompt = AIPromptRenderer.render(context: context).combined

        #expect(prompt.contains("Cover the complete selected text in its original order."))
        #expect(prompt.contains("If <anchored_context> contains <selected>...</selected> and the same text appears multiple times, use only the marked occurrence."))
        #expect(prompt.contains("<selected_text>\nFirst selected sentence.\n\nSecond selected sentence.\n</selected_text>"))
        #expect(prompt.contains("<selected>First selected sentence.</selected>"))
        #expect(prompt.contains("Use `$...$` for inline math and `$$...$$` for display math."))
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

        #expect(prompt.contains("The user selected the text inside <selected_text>. Use it as the main object of discussion."))
        #expect(prompt.contains("If the selected text contains multiple fragments, cover all relevant fragments in order."))
        #expect(prompt.contains("<selected_text>\nFirst claim.\nSecond claim.\n</selected_text>"))
        #expect(prompt.contains("If <anchored_context> contains <selected>...</selected> and the same text appears multiple times, use only the marked occurrence."))
    }
}
