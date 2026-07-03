import Testing
@testable import VellumCore

@Suite("AI selected text normalizer")
struct AISelectedTextNormalizerTests {
    @Test
    func joinsPDFLineWrappedParagraphs() {
        let text = """
        This paragraph was extracted
        as a stack of short visual
        lines from PDFKit even though
        it should be sent to the model
        as one coherent paragraph.
        """

        let normalized = AISelectedTextNormalizer.normalized(text)

        #expect(normalized == "This paragraph was extracted as a stack of short visual lines from PDFKit even though it should be sent to the model as one coherent paragraph.")
    }

    @Test
    func removesLineEndingHyphenation() {
        let text = "The inter-\nnational result is mis-\ntranslated when broken."

        let normalized = AISelectedTextNormalizer.normalized(text)

        #expect(normalized == "The international result is mistranslated when broken.")
    }

    @Test
    func preservesParagraphBreaksFromBlankLines() {
        let text = """
        First selected paragraph
        continues here.

        Second selected paragraph
        continues here.
        """

        let normalized = AISelectedTextNormalizer.normalized(text)

        #expect(normalized == "First selected paragraph continues here.\n\nSecond selected paragraph continues here.")
    }

    @Test
    func joinsCJKLinesWithoutInjectingSpaces() {
        let text = """
        这是一段被
        拆成多行的中文文本
        """

        let normalized = AISelectedTextNormalizer.normalized(text)

        #expect(normalized == "这是一段被拆成多行的中文文本")
    }
}
