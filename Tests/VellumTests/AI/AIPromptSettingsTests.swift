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
    func legacyDefaultPromptMigratesToLocalizedHeadings() {
        let suiteName = "AIPromptSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(AIPromptSettings.legacyEnglishHeadingTemplate, forKey: AIPromptSettings.promptTemplateKey)

        let configuration = AIPromptSettings.current(defaults: defaults)

        #expect(configuration.template == AIPromptSettings.defaultTemplate)
        #expect(configuration.template.contains("For Chinese output, use \"### 音标\", \"### 翻译\", and \"### 上下文解释\"."))
    }

    @Test
    func previousBuiltInPromptMigratesToPronunciationGuidance() {
        let suiteName = "AIPromptSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let previousTemplate = AIPromptSettings.defaultTemplate
            .replacingOccurrences(of: "\nSelection kind: {{selectionKind}}\nPronunciation requirement: {{pronunciationGuidance}}\n", with: "\n")
            .replacingOccurrences(of: "- Follow the pronunciation requirement near the selected text.\n- For a single natural-language word, name, or term in any source language, include the pronunciation section. Do not omit it.\n- Prefer standard IPA when reliable. If IPA is not reliable or not the most useful reading aid, use the source language's standard reading or romanization, such as pinyin for Chinese, kana or romaji for Japanese, romanization for Korean, or a standard transliteration for other scripts.\n- If the selected text is an acronym, formula, code, citation marker, or symbol sequence, omit pronunciation unless the context clearly treats it as a spoken term.", with: "- If the selected text is a single English word or a common English inflected form, include common UK and US IPA. If only one reliable pronunciation is known, provide one and say it may vary.\n- If the selected text is a short Chinese phrase, include pinyin.")
        defaults.set(previousTemplate, forKey: AIPromptSettings.promptTemplateKey)

        let configuration = AIPromptSettings.current(defaults: defaults)

        #expect(configuration.template == AIPromptSettings.defaultTemplate)
        #expect(configuration.template.contains("Pronunciation requirement: {{pronunciationGuidance}}"))
    }
}
