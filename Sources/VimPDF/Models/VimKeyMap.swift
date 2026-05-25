enum VimKeyMap {
    static func normalizedContinuousKey(_ key: String) -> String {
        switch key {
        case "+":
            return "="
        default:
            return key.lowercased()
        }
    }

    static func isContinuousKey(_ key: String) -> Bool {
        switch normalizedContinuousKey(key) {
        case "j", "k", "d", "u", "h", "l", "=", "-":
            return true
        default:
            return false
        }
    }

    static func isHandledKey(_ key: String, hasNavigableTextSelection: Bool) -> Bool {
        switch key {
        case "g", "G", "H", "L", "O", "\t", "a", "c", "j", "k", "d", "u", "h", "l", "m", " ", "f", "b", "+", "=", "-", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "z", "o", "t", "x", "]", "[":
            return true
        case "w", "e":
            return hasNavigableTextSelection
        default:
            let lowered = key.lowercased()
            return lowered != key && isHandledKey(
                lowered,
                hasNavigableTextSelection: hasNavigableTextSelection
            )
        }
    }

    static func lowercaseFallback(for key: String) -> String? {
        let lowered = key.lowercased()
        guard lowered != key else { return nil }

        switch lowered {
        case "a", "c", "j", "k", "d", "u", "h", "l", "m", "f", "b", "w", "e", "o", "t", "x", "z":
            return lowered
        default:
            return nil
        }
    }
}
