@preconcurrency import AppKit
import PDFKit

extension VellumPDFView {
    @discardableResult
    func vimNavigateTextSelection(_ key: String) -> Bool {
        let key = key.lowercased()
        guard ["h", "j", "k", "l", "w", "b", "e"].contains(key),
              let document,
              hasNavigableTextSelection else {
            return false
        }

        let pageStarts = textPageStarts(in: document)
        guard let totalLength = pageStarts.last, totalLength > 0 else { return false }

        if textSelectionNavigationState == nil {
            guard let range = currentSelectionCharacterRange(pageStarts: pageStarts) else { return false }
            textSelectionNavigationState = VimTextSelectionNavigationState(
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
        }

        guard var state = textSelectionNavigationState else { return false }
        var nextExtent: Int?
        var nextExtentCaret: VimTextCaret?
        var movementDirection = 0
        var scrollCaretAfterSelection: VimTextCaret?
        var useVisualSelection = false

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
            useVisualSelection = true
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
            scrollCaretAfterSelection = verticalMove?.caret
            state.preferredX = verticalMove?.preferredX ?? state.preferredX
            movementDirection = key == "j" ? 1 : -1
        default:
            return false
        }

        guard var extent = nextExtent else { return false }
        extent = min(max(extent, 0), totalLength)
        if !useVisualSelection, extent == state.anchorOffset {
            extent = min(max(state.anchorOffset + movementDirection, 0), totalLength)
        }
        if useVisualSelection {
            guard nextExtentCaret != nil,
                  !sameVisualCaret(nextExtentCaret, state.anchorCaret) else { return true }
        } else {
            guard extent != state.anchorOffset else { return true }
        }

        state.extentOffset = extent
        state.extentCaret = nextExtentCaret ?? textCaret(
            atInsertionOffset: state.extentOffset,
            preferTrailingEdge: state.extentOffset >= state.anchorOffset,
            pageStarts: pageStarts
        )

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
}
