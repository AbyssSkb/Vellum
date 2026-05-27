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
        case "w", "e", "y":
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
        case "a", "c", "j", "k", "d", "u", "h", "l", "m", "f", "b", "w", "e", "o", "t", "x", "y", "z":
            return lowered
        default:
            return nil
        }
    }

    static func command(for key: String) -> VimCommand? {
        switch key {
        case "\t", "t":
            return .toggleOutline
        case "H":
            return .previousTab
        case "L":
            return .nextTab
        case "X":
            return .restoreClosedTab
        case "O":
            return .openInNewTab
        case "j":
            return .scrollDown
        case "k":
            return .scrollUp
        case "d":
            return .largeScrollDown
        case "u":
            return .largeScrollUp
        case "h":
            return .scrollLeft
        case "l":
            return .scrollRight
        case "a":
            return .explainHighlightSelection
        case "c":
            return .cycleHighlightColor
        case "m":
            return .highlightSelection
        case "y":
            return .copySelection
        case " ", "f":
            return .pageDown
        case "b":
            return .pageUp
        case "+", "=":
            return .zoomIn
        case "-":
            return .zoomOut
        case "0":
            return .zoomPageFit
        case "z":
            return .zoomFit
        case "o":
            return .open
        case "x":
            return .closeTab
        case "]":
            return .nextTab
        case "[":
            return .previousTab
        default:
            return nil
        }
    }

    static func continuousCommand(for key: String) -> VimCommand? {
        switch key {
        case "j":
            return .scrollDown
        case "k":
            return .scrollUp
        case "d":
            return .largeScrollDown
        case "u":
            return .largeScrollUp
        case "h":
            return .scrollLeft
        case "l":
            return .scrollRight
        case "=":
            return .zoomIn
        case "-":
            return .zoomOut
        default:
            return nil
        }
    }
}
