#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vellum-core-check.XXXXXX")"
HARNESS="$CHECK_DIR/main.swift"
CHECK_BIN="$CHECK_DIR/check-core-logic"
trap 'rm -rf "$CHECK_DIR"' EXIT

cat > "$HARNESS" <<'SWIFT'
import Foundation

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
SWIFT

swiftc \
    "$ROOT_DIR/Sources/Vellum/Support/TokyoNight.swift" \
    "$ROOT_DIR/Sources/Vellum/Support/NSColorExtensions.swift" \
    "$ROOT_DIR/Sources/Vellum/Models/ReaderModels.swift" \
    "$ROOT_DIR/Sources/Vellum/Models/VimKeyState.swift" \
    "$ROOT_DIR/Sources/Vellum/Models/VimKeyMap.swift" \
    "$ROOT_DIR/Sources/Vellum/Models/VimInputController.swift" \
    "$HARNESS" \
    -o "$CHECK_BIN"

"$CHECK_BIN"
