@preconcurrency import AppKit
import PDFKit

extension VellumPDFView {
    @discardableResult
    func vimSwapTextSelectionEndpoint() -> Bool {
        guard let document, hasNavigableTextSelection,
              var state = textSelectionState(pageStarts: textPageStarts(in: document)) else { return false }

        completePendingRestoreBeforeUserInteraction()
        cancelPendingRestore()
        stopScrollAnimation()
        stopZoomState()
        swap(&state.anchorOffset, &state.extentOffset)
        swap(&state.anchorCaret, &state.extentCaret)
        state.preferredX = nil
        textSelectionNavigationState = state
        return true
    }

    @discardableResult
    func vimNavigateTextSelection(_ key: String, count: Int = 1) -> Bool {
        let key = key.lowercased()
        guard ["h", "j", "k", "l", "w", "b", "e", "^", "$"].contains(key),
              let document,
              hasNavigableTextSelection else {
            return false
        }

        let pageStarts = textPageStarts(in: document)
        guard let totalLength = pageStarts.last, totalLength > 0 else { return false }

        guard var state = textSelectionState(pageStarts: pageStarts) else { return false }
        let isLineBoundary = key == "^" || key == "$"
        let useVisualSelection = key == "j" || key == "k" || isLineBoundary
        var scrollCaretAfterSelection: VimTextCaret?
        var didMove = false
        for _ in 0..<(isLineBoundary ? 1 : min(max(count, 1), VimInputController.maximumRepeatCount)) {
            var nextExtent: Int?
            var nextExtentCaret: VimTextCaret?
            var movementDirection = 0

            switch key {
            case "h":
                nextExtent = state.extentOffset - 1
                movementDirection = -1
                state.preferredX = nil
            case "l":
                nextExtent = state.extentOffset + 1
                movementDirection = 1
                state.preferredX = nil
            case "b":
                nextExtent = wordBackwardOffset(from: state.extentOffset, in: document, pageStarts: pageStarts)
                movementDirection = -1
                state.preferredX = nil
            case "w":
                nextExtent = wordForwardOffset(from: state.extentOffset, in: document, pageStarts: pageStarts)
                movementDirection = 1
                state.preferredX = nil
            case "e":
                nextExtent = wordEndOffset(from: state.extentOffset, in: document, pageStarts: pageStarts)
                movementDirection = 1
                state.preferredX = nil
            case "j", "k":
                let verticalMove = verticalSelectionCaret(
                    from: state.extentCaret,
                    fallbackExtentOffset: state.extentOffset,
                    anchorOffset: state.anchorOffset,
                    anchorCaret: state.anchorCaret,
                    direction: key == "j" ? 1 : -1,
                    preferredX: state.preferredX,
                    pageStarts: pageStarts
                )
                nextExtent = verticalMove?.caret.offset
                nextExtentCaret = verticalMove?.caret
                state.preferredX = verticalMove?.preferredX ?? state.preferredX
                movementDirection = key == "j" ? 1 : -1
            case "^", "$":
                nextExtentCaret = lineBoundarySelectionCaret(
                    from: state.extentCaret,
                    fallbackExtentOffset: state.extentOffset,
                    anchorOffset: state.anchorOffset,
                    moveToEnd: key == "$",
                    pageStarts: pageStarts
                )
                nextExtent = nextExtentCaret?.offset
                state.preferredX = nil
            default:
                return false
            }

            guard var extent = nextExtent else { break }
            extent = min(max(extent, 0), totalLength)
            if !useVisualSelection, extent == state.anchorOffset {
                extent = min(max(state.anchorOffset + movementDirection, 0), totalLength)
            }
            if useVisualSelection {
                guard nextExtentCaret != nil,
                      !sameVisualCaret(nextExtentCaret, state.anchorCaret) else { break }
                if isLineBoundary, extent == state.anchorOffset { break }
            } else {
                guard extent != state.anchorOffset else { break }
            }

            let caret = nextExtentCaret ?? textCaret(
                atInsertionOffset: extent,
                preferTrailingEdge: extent >= state.anchorOffset,
                pageStarts: pageStarts
            )
            guard extent != state.extentOffset || (useVisualSelection && !sameVisualCaret(caret, state.extentCaret)) else { break }
            state.extentOffset = extent
            state.extentCaret = caret
            scrollCaretAfterSelection = nextExtentCaret
            didMove = true
        }
        guard didMove else { return true }

        let didApplySelection = useVisualSelection
            ? applyVisualTextSelection(anchorCaret: state.anchorCaret, extentCaret: state.extentCaret, pageStarts: pageStarts)
                || applyTextSelection(
                    anchorOffset: state.anchorOffset,
                    extentOffset: state.extentOffset,
                    pageStarts: pageStarts,
                    scrollToEndpoint: scrollCaretAfterSelection == nil
                )
            : applyTextSelection(
                anchorOffset: state.anchorOffset,
                extentOffset: state.extentOffset,
                pageStarts: pageStarts,
                scrollToEndpoint: scrollCaretAfterSelection == nil
            )

        guard didApplySelection else {
            textSelectionNavigationState = nil
            return false
        }

        if let scrollCaretAfterSelection {
            scrollTextCaretToVisible(scrollCaretAfterSelection)
        }

        textSelectionNavigationState = state
        return true
    }

    func textSelectionState(pageStarts: [Int]) -> VimTextSelectionNavigationState? {
        if let textSelectionNavigationState { return textSelectionNavigationState }
        guard let range = currentSelectionCharacterRange(pageStarts: pageStarts) else { return nil }
        let state = VimTextSelectionNavigationState(
            anchorOffset: range.start,
            extentOffset: range.end,
            preferredX: nil,
            anchorCaret: textCaret(
                atInsertionOffset: range.start,
                preferTrailingEdge: false,
                pageStarts: pageStarts
            ),
            extentCaret: textCaret(
                atInsertionOffset: range.end,
                preferTrailingEdge: true,
                pageStarts: pageStarts
            )
        )
        textSelectionNavigationState = state
        return state
    }
}
