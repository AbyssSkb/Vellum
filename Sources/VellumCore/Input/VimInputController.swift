struct VimInputController {
    static let maximumRepeatCount = 1000
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

    mutating func consumeRepeatCount() -> Int {
        defer { state.clearPendingInput() }
        guard !state.numericPrefix.isEmpty else { return 1 }
        return min(Int(state.numericPrefix) ?? Self.maximumRepeatCount, Self.maximumRepeatCount)
    }

    mutating func handleKeyDown(
        _ key: String,
        isRepeat: Bool,
        hasNavigableTextSelection: Bool,
        hasTextActionTarget: Bool
    ) -> VimInputAction {
        if !isRepeat, state.pendingKey == "g", key == "N" {
            return handleKey(key, hasNavigableTextSelection: hasNavigableTextSelection, hasTextActionTarget: hasTextActionTarget)
        }
        if isRepeat, ["G", "H", "L", "X", "O"].contains(key) {
            return .handled
        }
        if (!isRepeat || key != "N"), let action = handleUppercaseCommand(key) {
            state.clearPendingInput()
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
        if !isRepeat, !state.numericPrefix.isEmpty,
           let command = VimKeyMap.continuousCommand(for: normalizedKey), command.acceptsCount {
            return commandAction(command)
        }
        state.clearPendingInput()
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
            let pageNumber = state.consumeNumericPrefix()
            state.clearPendingInput()
            switch key {
            case "g":
                if let pageNumber {
                    return .command(.jumpToPage(pageNumber))
                }
                return .command(.firstPage)
            case "t":
                return .command(.nextTab)
            case "T":
                return .command(.previousTab)
            case "n":
                return .command(.nextHighlight)
            case "N":
                return .command(.previousHighlight)
            default:
                return .ignored
            }
        }

        switch key {
        case "g":
            state.pendingKey = "g"
            return .handled
        case "G":
            if let pageNumber = state.consumeNumericPrefix() {
                return .command(.jumpToPage(pageNumber))
            }
            return .command(.lastPage)
        default:
            if let command = VimKeyMap.command(for: key) {
                return commandAction(command)
            }

            guard let fallback = VimKeyMap.lowercaseFallback(for: key) else {
                state.clearPendingInput()
                return .ignored
            }
            return handleKey(
                fallback,
                hasNavigableTextSelection: hasNavigableTextSelection,
                hasTextActionTarget: hasTextActionTarget
            )
        }
    }

    private mutating func commandAction(_ command: VimCommand) -> VimInputAction {
        let hasCount = !state.numericPrefix.isEmpty
        let count = consumeRepeatCount()
        return .command(hasCount && command.acceptsCount ? .counted(command, count) : command)
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
            return commandAction(.searchPrevious)
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
