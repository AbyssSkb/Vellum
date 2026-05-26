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
        let length = min(text.length, pageStarts.last ?? text.length)
        var index = min(max(offset, 0), length)

        if index < length, characterClass(at: index, in: text) != .whitespace {
            let currentClass = characterClass(at: index, in: text)
            while index < length, characterClass(at: index, in: text) == currentClass {
                index += 1
            }
        }

        while index < length, characterClass(at: index, in: text) == .whitespace {
            index += 1
        }

        return index
    }

    func wordBackwardOffset(from offset: Int, in document: PDFDocument, pageStarts: [Int]) -> Int {
        let text = documentText(in: document) as NSString
        let length = min(text.length, pageStarts.last ?? text.length)
        var index = min(max(offset, 0), length) - 1

        while index > 0, characterClass(at: index, in: text) == .whitespace {
            index -= 1
        }

        guard index >= 0 else { return 0 }
        let targetClass = characterClass(at: index, in: text)
        while index > 0, characterClass(at: index - 1, in: text) == targetClass {
            index -= 1
        }

        return index
    }

    func wordEndOffset(from offset: Int, in document: PDFDocument, pageStarts: [Int]) -> Int {
        let text = documentText(in: document) as NSString
        let length = min(text.length, pageStarts.last ?? text.length)
        var index = min(max(offset, 0), length)

        while index < length, characterClass(at: index, in: text) == .whitespace {
            index += 1
        }

        guard index < length else { return length }
        let targetClass = characterClass(at: index, in: text)
        while index + 1 < length, characterClass(at: index + 1, in: text) == targetClass {
            index += 1
        }

        return min(length, index + 1)
    }

    func documentText(in document: PDFDocument) -> String {
        (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined()
    }

    func characterClass(at offset: Int, in text: NSString) -> VimTextCharacterClass {
        guard offset >= 0, offset < text.length,
              let scalar = UnicodeScalar(Int(text.character(at: offset))) else {
            return .punctuation
        }

        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return .whitespace
        }

        if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
            return .word
        }

        return .punctuation
    }

    func isNewlineCharacter(at offset: Int, in text: NSString?) -> Bool {
        guard let text,
              offset >= 0,
              offset < text.length,
              let scalar = UnicodeScalar(Int(text.character(at: offset))) else {
            return false
        }

        return CharacterSet.newlines.contains(scalar)
    }
}
