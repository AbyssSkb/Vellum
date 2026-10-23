@preconcurrency import AppKit
import PDFKit

final class SavedTextSelection {
    weak var document: PDFDocument?
    let selection: PDFSelection
    let navigationState: VimTextSelectionNavigationState?

    init(document: PDFDocument, selection: PDFSelection, navigationState: VimTextSelectionNavigationState?) {
        self.document = document
        self.selection = selection
        self.navigationState = navigationState
    }
}

extension VellumPDFView {
    func rememberTextSelection() {
        guard let document, let selection = currentSelection,
              hasNavigableTextSelection, !selection.pages.isEmpty,
              selection.pages.allSatisfy({ $0.document === document }),
              let copy = selection.copy() as? PDFSelection else { return }

        savedTextSelection = SavedTextSelection(
            document: document,
            selection: copy,
            navigationState: textSelectionNavigationState
        )
    }

    func vimRestoreTextSelection() {
        guard let document, let saved = savedTextSelection,
              saved.document === document, !saved.selection.pages.isEmpty,
              saved.selection.pages.allSatisfy({ $0.document === document }) else {
            savedTextSelection = nil
            showNotification(AppUILanguage.saved().text(.noPreviousTextSelection))
            return
        }

        completePendingRestoreBeforeUserInteraction()
        cancelPendingRestore()
        stopScrollAnimation()
        stopZoomState()
        let previous = readingDestination()
        searchController?.hideMatches()
        setCurrentSelection(saved.selection.copy() as? PDFSelection ?? saved.selection, animate: false)
        textSelectionNavigationState = saved.navigationState
        savedTextSelection = saved

        if let caret = saved.navigationState?.extentCaret {
            scrollTextCaretToVisible(caret)
        } else {
            let pageStarts = textPageStarts(in: document)
            if let state = saved.navigationState {
                scrollTextSelectionEndpointToVisible(
                    anchorOffset: state.anchorOffset,
                    extentOffset: state.extentOffset,
                    pageStarts: pageStarts
                )
            } else if let range = currentSelectionCharacterRange(pageStarts: pageStarts) {
                scrollTextSelectionEndpointToVisible(
                    anchorOffset: range.start,
                    extentOffset: range.end,
                    pageStarts: pageStarts
                )
            }
        }
        needsDisplay = true
        focus()
        scheduleReadingPositionReport(userNavigated: readingPositionChanged(from: previous))
    }
}
