import Foundation
import Testing
@testable import VellumCore

@Suite("AI explanation pronunciation speech")
struct AIExplanationPronunciationSpeechTests {
    @Test
    func usesSelectedTextAsSpeechTarget() {
        let target = AIExplanationPronunciationSpeech.speechText(
            selectedText: "  salient\nfactor  ",
            markdown: "### 音标\n/səˈliːənt/"
        )

        #expect(target == "salient factor")
    }

    @Test
    func recognizesLocalizedPronunciationHeadings() {
        #expect(AIExplanationPronunciationSpeech.isPronunciationHeading("音标"))
        #expect(AIExplanationPronunciationSpeech.isPronunciationHeading("Pronunciation"))
        #expect(AIExplanationPronunciationSpeech.isPronunciationHeading("Reading:"))
    }

    @Test
    func doesNotUseBareIPAAsFallbackSpeechTarget() {
        let target = AIExplanationPronunciationSpeech.speechText(
            selectedText: nil,
            markdown: "### 音标\n/səˈliːənt/"
        )

        #expect(target == nil)
    }

    @Test
    func canUseRomanizationFallbackWhenNoSelectionTextExists() {
        let target = AIExplanationPronunciationSpeech.speechText(
            selectedText: nil,
            markdown: "### 音标\n- pinyin: lu jing yi lai"
        )

        #expect(target == "pinyin: lu jing yi lai")
    }
}
