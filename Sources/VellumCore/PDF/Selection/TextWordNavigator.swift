import Foundation

enum TextWordNavigator {
    static func wordForwardOffset(from offset: Int, in text: NSString, lengthLimit: Int? = nil) -> Int {
        wordForwardOffset(from: offset, length: min(text.length, lengthLimit ?? text.length)) {
            characterClass(at: $0, in: text)
        }
    }

    static func wordForwardOffset(from offset: Int, length: Int, characterClass: (Int) -> VimTextCharacterClass) -> Int {
        var index = min(max(offset, 0), length)

        if index < length, characterClass(index) != .whitespace {
            let currentClass = characterClass(index)
            while index < length, characterClass(index) == currentClass {
                index += 1
            }
        }

        while index < length, characterClass(index) == .whitespace {
            index += 1
        }

        return index
    }

    static func wordBackwardOffset(from offset: Int, in text: NSString, lengthLimit: Int? = nil) -> Int {
        wordBackwardOffset(from: offset, length: min(text.length, lengthLimit ?? text.length)) {
            characterClass(at: $0, in: text)
        }
    }

    static func wordBackwardOffset(from offset: Int, length: Int, characterClass: (Int) -> VimTextCharacterClass) -> Int {
        var index = min(max(offset, 0), length) - 1

        while index > 0, characterClass(index) == .whitespace {
            index -= 1
        }

        guard index >= 0 else { return 0 }
        let targetClass = characterClass(index)
        while index > 0, characterClass(index - 1) == targetClass {
            index -= 1
        }

        return index
    }

    static func wordEndOffset(from offset: Int, in text: NSString, lengthLimit: Int? = nil) -> Int {
        wordEndOffset(from: offset, length: min(text.length, lengthLimit ?? text.length)) {
            characterClass(at: $0, in: text)
        }
    }

    static func wordEndOffset(from offset: Int, length: Int, characterClass: (Int) -> VimTextCharacterClass) -> Int {
        var index = min(max(offset, 0), length)

        while index < length, characterClass(index) == .whitespace {
            index += 1
        }

        guard index < length else { return length }
        let targetClass = characterClass(index)
        while index + 1 < length, characterClass(index + 1) == targetClass {
            index += 1
        }

        return min(length, index + 1)
    }

    static func characterClass(at offset: Int, in text: NSString) -> VimTextCharacterClass {
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

    static func isNewlineCharacter(at offset: Int, in text: NSString?) -> Bool {
        guard let text,
              offset >= 0,
              offset < text.length,
              let scalar = UnicodeScalar(Int(text.character(at: offset))) else {
            return false
        }

        return CharacterSet.newlines.contains(scalar)
    }
}
