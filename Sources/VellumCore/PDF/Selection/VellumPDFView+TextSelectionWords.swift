@preconcurrency import AppKit
import PDFKit
extension VellumPDFView {
    func textPageStarts(in document: PDFDocument) -> [Int] {
        textSelectionCache.pageStarts(in: document)
    }

    func wordForwardOffset(from offset: Int, in document: PDFDocument, pageStarts: [Int]) -> Int {
        TextWordNavigator.wordForwardOffset(from: offset, length: pageStarts.last ?? 0) {
            characterClass(at: $0, in: document, pageStarts: pageStarts)
        }
    }

    func wordBackwardOffset(from offset: Int, in document: PDFDocument, pageStarts: [Int]) -> Int {
        TextWordNavigator.wordBackwardOffset(from: offset, length: pageStarts.last ?? 0) {
            characterClass(at: $0, in: document, pageStarts: pageStarts)
        }
    }

    func wordEndOffset(from offset: Int, in document: PDFDocument, pageStarts: [Int]) -> Int {
        TextWordNavigator.wordEndOffset(from: offset, length: pageStarts.last ?? 0) {
            characterClass(at: $0, in: document, pageStarts: pageStarts)
        }
    }

    func documentText(in document: PDFDocument) -> NSString {
        textSelectionCache.text(in: document)
    }

    func characterClass(at offset: Int, in text: NSString) -> VimTextCharacterClass {
        TextWordNavigator.characterClass(at: offset, in: text)
    }

    private func characterClass(at offset: Int, in document: PDFDocument, pageStarts: [Int]) -> VimTextCharacterClass {
        guard let pageIndex = pageIndex(containing: offset, pageStarts: pageStarts),
              let page = document.page(at: pageIndex),
              let text = textSelectionCache.text(on: page, in: document) else { return .punctuation }
        return TextWordNavigator.characterClass(at: offset - pageStarts[pageIndex], in: text)
    }

    func isNewlineCharacter(at offset: Int, in text: NSString?) -> Bool {
        TextWordNavigator.isNewlineCharacter(at: offset, in: text)
    }
}
