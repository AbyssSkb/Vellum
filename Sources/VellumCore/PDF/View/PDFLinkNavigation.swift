@preconcurrency import PDFKit

enum PDFLinkNavigation {
    static func shouldRecordJumpSource(for annotation: PDFAnnotation?) -> Bool {
        guard let annotation,
              annotation.type == "Link" else { return false }

        if annotation.destination != nil {
            return true
        }

        return shouldRecordJumpSource(for: annotation.action)
    }

    static func shouldRecordJumpSource(for action: PDFAction?) -> Bool {
        if action is PDFActionGoTo { return true }
        guard let action = action as? PDFActionNamed else { return false }
        switch action.name {
        case .nextPage, .previousPage, .firstPage, .lastPage, .goBack, .goForward, .goToPage:
            return true
        default:
            return false
        }
    }
}

extension VellumPDFView {
    func vimPerformPDFAction(_ action: PDFAction) {
        if let action = action as? PDFActionGoTo {
            vimGoToDestination(action.destination)
            return
        }

        searchController?.markReaderNavigated()
        cancelPendingRestore()
        stopScrollAnimation()
        stopZoomState()
        if PDFLinkNavigation.shouldRecordJumpSource(for: action) {
            recordJumpSource()
        }
        perform(action)
    }
}
