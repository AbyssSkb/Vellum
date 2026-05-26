@preconcurrency import AppKit
import PDFKit
extension VellumPDFView {
    func textPageStarts(in document: PDFDocument) -> [Int] {
        var starts: [Int] = []
        var offset = 0

        for pageIndex in 0..<document.pageCount {
            starts.append(offset)
            offset += document.page(at: pageIndex)?.numberOfCharacters ?? 0
        }

        starts.append(offset)
        return starts
    }

    func wordForwardOffset(from offset: Int, in document: PDFDocument, pageStarts: [Int]) -> Int {
        let text = documentText(in: document) as NSString
        return TextWordNavigator.wordForwardOffset(from: offset, in: text, lengthLimit: pageStarts.last)
    }

    func wordBackwardOffset(from offset: Int, in document: PDFDocument, pageStarts: [Int]) -> Int {
        let text = documentText(in: document) as NSString
        return TextWordNavigator.wordBackwardOffset(from: offset, in: text, lengthLimit: pageStarts.last)
    }

    func wordEndOffset(from offset: Int, in document: PDFDocument, pageStarts: [Int]) -> Int {
        let text = documentText(in: document) as NSString
        return TextWordNavigator.wordEndOffset(from: offset, in: text, lengthLimit: pageStarts.last)
    }

    func documentText(in document: PDFDocument) -> String {
        (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined()
    }

    func characterClass(at offset: Int, in text: NSString) -> VimTextCharacterClass {
        TextWordNavigator.characterClass(at: offset, in: text)
    }

    func isNewlineCharacter(at offset: Int, in text: NSString?) -> Bool {
        TextWordNavigator.isNewlineCharacter(at: offset, in: text)
    }
}
