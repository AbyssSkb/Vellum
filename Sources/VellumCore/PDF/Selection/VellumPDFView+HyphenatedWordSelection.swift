@preconcurrency import AppKit
import PDFKit

extension VellumPDFView {
    func smartWordSelection(at pointOnPage: NSPoint, on page: PDFPage) -> PDFSelection? {
        guard let selection = page.selectionForWord(at: pointOnPage) else { return nil }
        return hyphenatedWordSelection(from: selection, on: page) ?? selection
    }

    func hyphenatedWordSelection(from selection: PDFSelection, on page: PDFPage) -> PDFSelection? {
        guard let pageText = page.string as NSString?,
              pageText.length > 0,
              let selectedRange = textRange(for: selection, on: page) else {
            return nil
        }

        let expandedRange = Self.hyphenatedWordRange(in: pageText, selectedRange: selectedRange)
        guard expandedRange.location != selectedRange.location
                || expandedRange.length != selectedRange.length else {
            return nil
        }

        return page.selection(for: expandedRange)
    }

    static func hyphenatedWordRange(in text: NSString, selectedRange: NSRange) -> NSRange {
        let clampedRange = selectedRange.clamped(toLength: text.length)
        guard clampedRange.length > 0 else { return clampedRange }

        var start = clampedRange.location
        var end = clampedRange.location + clampedRange.length

        while start > 0, isWordCharacter(text.character(at: start - 1)) {
            start -= 1
        }
        while end < text.length, isWordCharacter(text.character(at: end)) {
            end += 1
        }

        while let previousStart = previousHyphenatedWordStart(before: start, in: text) {
            start = previousStart
        }

        while let nextEnd = nextHyphenatedWordEnd(after: end, in: text) {
            end = nextEnd
        }

        return NSRange(location: start, length: end - start)
    }

    private func textRange(for selection: PDFSelection, on page: PDFPage) -> NSRange? {
        let rangeCount = selection.numberOfTextRanges(on: page)
        guard rangeCount > 0 else { return nil }

        var lowerBound = Int.max
        var upperBound = 0
        for rangeIndex in 0..<rangeCount {
            let range = selection.range(at: rangeIndex, on: page)
            guard range.location != NSNotFound, range.length > 0 else { continue }

            lowerBound = min(lowerBound, range.location)
            upperBound = max(upperBound, range.location + range.length)
        }

        guard lowerBound < upperBound else { return nil }
        return NSRange(location: lowerBound, length: upperBound - lowerBound)
    }

    private static func previousHyphenatedWordStart(before rangeStart: Int, in text: NSString) -> Int? {
        var index = rangeStart

        while index > 0, isHorizontalWhitespace(text.character(at: index - 1)) {
            index -= 1
        }

        var sawLineBreak = false
        while index > 0, isLineBreak(text.character(at: index - 1)) {
            sawLineBreak = true
            index -= 1
        }
        guard sawLineBreak else { return nil }

        while index > 0, isHorizontalWhitespace(text.character(at: index - 1)) {
            index -= 1
        }

        guard index > 0, isHyphen(text.character(at: index - 1)) else { return nil }
        let hyphenIndex = index - 1
        guard hyphenIndex > 0, isWordCharacter(text.character(at: hyphenIndex - 1)) else { return nil }

        var wordStart = hyphenIndex - 1
        while wordStart > 0, isWordCharacter(text.character(at: wordStart - 1)) {
            wordStart -= 1
        }

        return wordStart
    }

    private static func nextHyphenatedWordEnd(after rangeEnd: Int, in text: NSString) -> Int? {
        var index = rangeEnd

        if index < text.length, isHyphen(text.character(at: index)) {
            index += 1
        } else if index > 0, isHyphen(text.character(at: index - 1)) {
            // PDFKit sometimes includes the trailing hyphen in selectionForWord(at:).
        } else {
            return nil
        }

        while index < text.length, isHorizontalWhitespace(text.character(at: index)) {
            index += 1
        }

        var sawLineBreak = false
        while index < text.length, isLineBreak(text.character(at: index)) {
            sawLineBreak = true
            index += 1
        }
        guard sawLineBreak else { return nil }

        while index < text.length, isHorizontalWhitespace(text.character(at: index)) {
            index += 1
        }

        guard index < text.length, isWordCharacter(text.character(at: index)) else { return nil }

        var wordEnd = index + 1
        while wordEnd < text.length, isWordCharacter(text.character(at: wordEnd)) {
            wordEnd += 1
        }

        return wordEnd
    }

    private static func isWordCharacter(_ character: unichar) -> Bool {
        guard let scalar = UnicodeScalar(Int(character)) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || character == 95
    }

    private static func isHyphen(_ character: unichar) -> Bool {
        character == 45
            || character == 0x2010
            || character == 0x2011
            || character == 0x2012
            || character == 0x2013
            || character == 0x2212
    }

    private static func isLineBreak(_ character: unichar) -> Bool {
        character == 10 || character == 13
    }

    private static func isHorizontalWhitespace(_ character: unichar) -> Bool {
        character == 9 || character == 32 || character == 0x00A0
    }
}

private extension NSRange {
    func clamped(toLength length: Int) -> NSRange {
        guard location != NSNotFound, length > 0 else {
            return NSRange(location: 0, length: 0)
        }

        let clampedLocation = max(0, min(location, length))
        let upperBound = max(clampedLocation, min(location + self.length, length))
        return NSRange(location: clampedLocation, length: upperBound - clampedLocation)
    }
}
