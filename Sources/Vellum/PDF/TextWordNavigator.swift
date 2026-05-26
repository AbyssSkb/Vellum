import Foundation

enum TextWordNavigator {
    static func wordForwardOffset(from offset: Int, in text: NSString, lengthLimit: Int? = nil) -> Int {
        let length = min(text.length, lengthLimit ?? text.length)
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

    static func wordBackwardOffset(from offset: Int, in text: NSString, lengthLimit: Int? = nil) -> Int {
        let length = min(text.length, lengthLimit ?? text.length)
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

    static func wordEndOffset(from offset: Int, in text: NSString, lengthLimit: Int? = nil) -> Int {
        let length = min(text.length, lengthLimit ?? text.length)
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
