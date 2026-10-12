import Testing
@testable import VellumCore

@Suite("AI selected text normalizer")
struct AISelectedTextNormalizerTests {
    @Test(arguments: [
        (
            """
            This paragraph was extracted
            as a stack of short visual
            lines from PDFKit even though
            it should be sent to the model
            as one coherent paragraph.
            """,
            "This paragraph was extracted as a stack of short visual lines from PDFKit even though it should be sent to the model as one coherent paragraph."
        ),
        (
            "The inter-\nnational result is mis-\ntranslated when broken.",
            "The international result is mistranslated when broken."
        ),
        (
            """
            First selected paragraph
            continues here.

            Second selected paragraph
            continues here.
            """,
            "First selected paragraph continues here.\n\nSecond selected paragraph continues here."
        ),
        ("这是一段被\n拆成多行的中文文本", "这是一段被拆成多行的中文文本")
    ])
    func normalizesVisualLinesPreservingParagraphsAndLanguage(input: String, expected: String) {
        #expect(AISelectedTextNormalizer.normalized(input) == expected)
    }
}
