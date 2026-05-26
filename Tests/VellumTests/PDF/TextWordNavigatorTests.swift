import Foundation
import Testing
@testable import Vellum

@Suite("Text word navigator")
struct TextWordNavigatorTests {
    @Test
    func forwardSkipsCurrentWordAndWhitespace() {
        let text = "alpha  beta.gamma" as NSString

        #expect(TextWordNavigator.wordForwardOffset(from: 0, in: text) == 7)
        #expect(TextWordNavigator.wordForwardOffset(from: 7, in: text) == 11)
        #expect(TextWordNavigator.wordForwardOffset(from: 11, in: text) == 12)
    }

    @Test
    func backwardFindsStartOfPreviousClassRun() {
        let text = "alpha  beta.gamma" as NSString

        #expect(TextWordNavigator.wordBackwardOffset(from: 17, in: text) == 12)
        #expect(TextWordNavigator.wordBackwardOffset(from: 12, in: text) == 11)
        #expect(TextWordNavigator.wordBackwardOffset(from: 7, in: text) == 0)
    }

    @Test
    func endStopsAfterCurrentClassRun() {
        let text = " alpha beta.gamma" as NSString

        #expect(TextWordNavigator.wordEndOffset(from: 0, in: text) == 6)
        #expect(TextWordNavigator.wordEndOffset(from: 7, in: text) == 11)
        #expect(TextWordNavigator.wordEndOffset(from: 11, in: text) == 12)
    }

    @Test
    func lengthLimitClampsNavigation() {
        let text = "alpha beta gamma" as NSString

        #expect(TextWordNavigator.wordForwardOffset(from: 7, in: text, lengthLimit: 10) == 10)
        #expect(TextWordNavigator.wordEndOffset(from: 7, in: text, lengthLimit: 10) == 10)
        #expect(TextWordNavigator.wordBackwardOffset(from: 99, in: text, lengthLimit: 10) == 6)
    }

    @Test
    func characterClassGroupsWordWhitespaceAndPunctuation() {
        let text = "a_\n." as NSString

        #expect(TextWordNavigator.characterClass(at: 0, in: text) == .word)
        #expect(TextWordNavigator.characterClass(at: 1, in: text) == .word)
        #expect(TextWordNavigator.characterClass(at: 2, in: text) == .whitespace)
        #expect(TextWordNavigator.characterClass(at: 3, in: text) == .punctuation)
        #expect(TextWordNavigator.characterClass(at: 99, in: text) == .punctuation)
    }

    @Test
    func newlineDetectionHandlesBoundsAndNilText() {
        let text = "a\nb" as NSString

        #expect(TextWordNavigator.isNewlineCharacter(at: 1, in: text))
        #expect(!TextWordNavigator.isNewlineCharacter(at: 0, in: text))
        #expect(!TextWordNavigator.isNewlineCharacter(at: 3, in: text))
        #expect(!TextWordNavigator.isNewlineCharacter(at: 0, in: nil))
    }
}
