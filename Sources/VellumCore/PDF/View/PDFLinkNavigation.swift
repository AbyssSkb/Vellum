@preconcurrency import PDFKit

enum PDFLinkNavigation {
    static func previewDestination(for annotation: PDFAnnotation, in document: PDFDocument) -> PDFDestination? {
        guard let destination = (action(for: annotation) as? PDFActionGoTo)?.destination,
              let page = destination.page, page.document === document,
              document.index(for: page) != NSNotFound else { return nil }
        return destination
    }

    static func action(for annotation: PDFAnnotation) -> PDFAction? {
        if let destination = annotation.destination {
            return PDFActionGoTo(destination: destination)
        }
        if let action = annotation.action { return action }
        return annotation.url.map(PDFActionURL.init(url:))
    }

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
        let previous = readingDestination()
        cancelPendingRestore()
        stopScrollAnimation()
        stopZoomState()
        if PDFLinkNavigation.shouldRecordJumpSource(for: action) {
            recordJumpSource()
        }
        perform(action)
        if PDFLinkNavigation.shouldRecordJumpSource(for: action) {
            let generation = restoreGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.restoreGeneration == generation else { return }
                self.scheduleReadingPositionReport(userNavigated: self.readingPositionChanged(from: previous))
            }
        }
    }

    func reportInternalLinkNavigation(_ annotation: PDFAnnotation, from previous: PDFDestination?, generation: Int) {
        guard generation == restoreGeneration, PDFLinkNavigation.shouldRecordJumpSource(for: annotation) else { return }
        if let destination = annotation.destination ?? (annotation.action as? PDFActionGoTo)?.destination,
           destination.page?.document === document {
            pinReadingSection(at: destination)
        } else {
            scheduleReadingPositionReport(userNavigated: readingPositionChanged(from: previous))
        }
    }
}
