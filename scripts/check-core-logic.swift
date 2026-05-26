#!/usr/bin/env swift

import Foundation

struct VimKeyState {
    var pendingKey: String?
    var numericPrefix = ""
    var heldKey: String?

    mutating func clearPendingInput() {
        numericPrefix = ""
        pendingKey = nil
    }

    mutating func handleNumericPrefixKey(_ key: String) -> Bool {
        switch key {
        case "1"..."9":
            numericPrefix.append(key)
            pendingKey = nil
            return true
        case "0" where !numericPrefix.isEmpty:
            numericPrefix.append(key)
            pendingKey = nil
            return true
        default:
            return false
        }
    }

    mutating func consumeNumericPrefix() -> Int? {
        defer { numericPrefix = "" }
        return Int(numericPrefix)
    }
}

enum VimCommand: Equatable {
    case firstPage
    case lastPage
    case jumpToPage(Int)
    case nextTab
    case previousTab
    case restoreClosedTab
    case openInNewTab
    case zoomIn
}

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

    static func continuousCommand(for key: String) -> VimCommand? {
        switch key {
        case "=":
            return .zoomIn
        default:
            return nil
        }
    }
}

struct VimInputController {
    private(set) var state = VimKeyState()

    var heldKey: String? {
        state.heldKey
    }

    mutating func clearPendingInput() {
        state.clearPendingInput()
    }

    mutating func clearHeldKey() {
        state.heldKey = nil
    }

    mutating func beginHeldKey(_ key: String) {
        state.heldKey = key
    }

    mutating func handleKeyDown(
        _ key: String,
        isRepeat: Bool,
        hasNavigableTextSelection: Bool
    ) -> VimInputAction {
        if let action = handleUppercaseCommand(key) {
            return action
        }

        guard VimKeyMap.isContinuousKey(key) else {
            if isRepeat {
                return VimKeyMap.isHandledKey(
                    key,
                    hasNavigableTextSelection: hasNavigableTextSelection
                ) ? .handled : .ignored
            }
            return handleKey(key)
        }

        let normalizedKey = VimKeyMap.normalizedContinuousKey(key)
        if state.heldKey == normalizedKey {
            return .handled
        }

        state.heldKey = normalizedKey
        return .continuousKey(normalizedKey)
    }

    mutating func handleKeyUp(_ key: String) -> VimInputAction {
        guard VimKeyMap.isContinuousKey(key),
              state.heldKey == VimKeyMap.normalizedContinuousKey(key) else { return .ignored }
        state.heldKey = nil
        return .stopContinuousKey
    }

    mutating func handleKey(_ key: String) -> VimInputAction {
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
            state.numericPrefix = ""
            guard let fallback = VimKeyMap.lowercaseFallback(for: key) else { return .ignored }
            return handleKey(fallback)
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

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write("Check failed: \(message)\n".data(using: .utf8)!)
        exit(1)
    }
}

var keyState = VimKeyState()
expect(!keyState.handleNumericPrefixKey("0"), "numeric prefix should not start with 0")
expect(keyState.handleNumericPrefixKey("1"), "numeric prefix should accept non-zero start")
expect(keyState.handleNumericPrefixKey("0"), "numeric prefix should accept trailing zero")
expect(keyState.consumeNumericPrefix() == 10, "numeric prefix should parse 10")
expect(keyState.numericPrefix.isEmpty, "consume should clear numeric prefix")

keyState = VimKeyState(pendingKey: "g", numericPrefix: "12", heldKey: "j")
keyState.clearPendingInput()
expect(keyState.pendingKey == nil, "clearPendingInput should clear pending key")
expect(keyState.numericPrefix.isEmpty, "clearPendingInput should clear numeric prefix")
expect(keyState.heldKey == "j", "clearPendingInput should keep held key")

expect(VimKeyMap.normalizedContinuousKey("+") == "=", "+ should normalize to =")
expect(VimKeyMap.isContinuousKey("+"), "+ should be continuous")
expect(VimKeyMap.continuousCommand(for: "=") == .zoomIn, "= should map to zoom in")
expect(!VimKeyMap.isHandledKey("w", hasNavigableTextSelection: false), "w should require navigable selection")
expect(VimKeyMap.isHandledKey("w", hasNavigableTextSelection: true), "w should work with navigable selection")
expect(VimKeyMap.lowercaseFallback(for: "A") == "a", "A should fall back to a")
expect(VimKeyMap.lowercaseFallback(for: "G") == nil, "G should remain a dedicated uppercase command")

var input = VimInputController()
expect(input.handleKeyDown("g", isRepeat: false, hasNavigableTextSelection: false) == .handled, "g should start a pending key")
expect(input.handleKeyDown("g", isRepeat: false, hasNavigableTextSelection: false) == .command(.firstPage), "gg should go to first page")

input = VimInputController()
expect(input.handleKeyDown("1", isRepeat: false, hasNavigableTextSelection: false) == .handled, "1 should start numeric prefix")
expect(input.handleKeyDown("2", isRepeat: false, hasNavigableTextSelection: false) == .handled, "2 should continue numeric prefix")
expect(input.handleKeyDown("G", isRepeat: false, hasNavigableTextSelection: false) == .command(.jumpToPage(12)), "12G should jump to page 12")

input = VimInputController()
expect(input.handleKeyDown("j", isRepeat: false, hasNavigableTextSelection: false) == .continuousKey("j"), "j should start continuous scroll")
expect(input.handleKeyDown("j", isRepeat: true, hasNavigableTextSelection: false) == .handled, "repeat j should stay handled")
expect(input.handleKeyUp("j") == .stopContinuousKey, "j keyUp should stop continuous scroll")
expect(input.heldKey == nil, "keyUp should clear held key")

print("Core logic checks passed.")
