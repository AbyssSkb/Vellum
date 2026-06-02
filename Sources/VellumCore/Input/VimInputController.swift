struct VimInputController {
    private(set) var state = VimKeyState()

    var heldKey: String? {
        state.heldKey
    }

    mutating func clearPendingInput() {
        state.clearPendingInput()
    }

    mutating func clearHeldKey() {
        state.clearHeldKey()
    }

    mutating func beginHeldKey(_ key: String) {
        state.heldKey = key
    }

    mutating func handleKeyDown(
        _ key: String,
        isRepeat: Bool,
        hasNavigableTextSelection: Bool,
        hasTextActionTarget: Bool
    ) -> VimInputAction {
        if let action = handleUppercaseCommand(key) {
            return action
        }

        guard VimKeyMap.isContinuousKey(key) else {
            if isRepeat {
                if let command = VimKeyMap.repeatableCommand(for: key) {
                    state.clearPendingInput()
                    return .command(command)
                }
                return VimKeyMap.isHandledKey(
                    key,
                    hasNavigableTextSelection: hasNavigableTextSelection,
                    hasTextActionTarget: hasTextActionTarget
                ) ? .handled : .ignored
            }
            return handleKey(
                key,
                hasNavigableTextSelection: hasNavigableTextSelection,
                hasTextActionTarget: hasTextActionTarget
            )
        }

        let normalizedKey = VimKeyMap.normalizedContinuousKey(key)
        if state.heldKey == normalizedKey {
            return .handled
        }

        state.heldKey = normalizedKey
        return .continuousKey(normalizedKey)
    }

    mutating func handleKeyUp(_ key: String) -> VimInputAction {
        guard let heldKey = state.heldKey,
              VimKeyMap.isReleaseForHeldContinuousKey(key, heldKey: heldKey) else { return .ignored }
        state.clearHeldKey()
        return .stopContinuousKey
    }

    mutating func handleKey(
        _ key: String,
        hasNavigableTextSelection: Bool = true,
        hasTextActionTarget: Bool = true
    ) -> VimInputAction {
        if state.handleNumericPrefixKey(key) {
            return .handled
        }

        if state.pendingKey == "g" {
            state.clearPendingInput()
            switch key {
            case "g":
                return .command(.firstPage)
            case "t":
                return .command(.nextTab)
            case "T":
                return .command(.previousTab)
            default:
                return .ignored
            }
        }

        switch key {
        case "y" where !hasTextActionTarget:
            state.clearPendingInput()
            return .ignored
        case "g":
            state.numericPrefix = ""
            state.pendingKey = "g"
            return .handled
        case "G":
            if let pageNumber = state.consumeNumericPrefix() {
                return .command(.jumpToPage(pageNumber))
            }
            return .command(.lastPage)
        default:
            if let command = VimKeyMap.command(for: key) {
                state.clearPendingInput()
                return .command(command)
            }

            state.numericPrefix = ""
            guard let fallback = VimKeyMap.lowercaseFallback(for: key) else { return .ignored }
            return handleKey(
                fallback,
                hasNavigableTextSelection: hasNavigableTextSelection,
                hasTextActionTarget: hasTextActionTarget
            )
        }
    }

    private mutating func handleUppercaseCommand(_ key: String) -> VimInputAction? {
        switch key {
        case "G":
            if let pageNumber = state.consumeNumericPrefix() {
                return .command(.jumpToPage(pageNumber))
            }
            return .command(.lastPage)
        case "H":
            state.numericPrefix = ""
            return .command(.previousTab)
        case "L":
            state.numericPrefix = ""
            return .command(.nextTab)
        case "X":
            state.numericPrefix = ""
            return .command(.restoreClosedTab)
        case "O":
            state.numericPrefix = ""
            return .command(.openInNewTab)
        case "N":
            state.numericPrefix = ""
            return .command(.searchPrevious)
        default:
            return nil
        }
    }
}

enum VimInputAction: Equatable {
    case ignored
    case handled
    case command(VimCommand)
    case continuousKey(String)
    case stopContinuousKey
}
