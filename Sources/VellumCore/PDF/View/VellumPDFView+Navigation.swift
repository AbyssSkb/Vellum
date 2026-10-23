@preconcurrency import AppKit
import PDFKit

extension VellumPDFView {
    func vimGoToFirstPage() {
        let previous = readingDestination()
        searchController?.markReaderNavigated()
        cancelPendingRestore()
        let generation = restoreGeneration
        recordJumpSource()
        stopScrollAnimation()
        stopZoomState()
        goToFirstPage(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.restoreGeneration == generation else { return }
            self.scrollToDocumentEdge(.top)
            self.scheduleReadingPositionReport(userNavigated: self.readingPositionChanged(from: previous))
        }
    }

    func vimGoToLastPage() {
        let previous = readingDestination()
        searchController?.markReaderNavigated()
        cancelPendingRestore()
        let generation = restoreGeneration
        recordJumpSource()
        stopScrollAnimation()
        stopZoomState()
        goToLastPage(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.restoreGeneration == generation else { return }
            self.scrollToDocumentEdge(.bottom)
            self.scheduleReadingPositionReport(userNavigated: self.readingPositionChanged(from: previous))
        }
    }

    func vimGoToPage(_ pageNumber: Int) {
        guard let document, document.pageCount > 0 else { return }

        let pageCount = document.pageCount
        let pageIndex = min(max(pageNumber, 1), pageCount) - 1
        guard let page = document.page(at: pageIndex) else { return }
        let previous = readingDestination()

        searchController?.markReaderNavigated()
        cancelPendingRestore()
        let generation = restoreGeneration
        recordJumpSource()
        stopScrollAnimation()
        stopZoomState()

        let destination = topDestination(for: page)
        go(to: destination)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.restoreGeneration == generation else { return }
            self.go(to: destination)
            self.scheduleReadingPositionReport(userNavigated: self.readingPositionChanged(from: previous))
            if pageNumber < 1 || pageNumber > pageCount {
                self.showNotification(AppUILanguage.saved().text(.pageNumberOutOfRange(pageCount)))
            }
        }
    }

    func vimGoToDestination(_ destination: PDFDestination) {
        pendingReadingNavigation = false
        let horizontalOrigin = currentHorizontalOrigin()

        searchController?.markReaderNavigated()
        cancelPendingRestore()
        let generation = restoreGeneration
        recordJumpSource()
        stopScrollAnimation()
        stopZoomState()

        go(to: destination)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.restoreGeneration == generation else { return }
            self.go(to: destination)
            self.restoreHorizontalOrigin(horizontalOrigin)

            DispatchQueue.main.async { [weak self] in
                guard let self, self.restoreGeneration == generation else { return }
                self.restoreHorizontalOrigin(horizontalOrigin)
                self.scheduleReadingPositionReport()
            }
        }
    }

    func vimJumpBack() {
        guard let targetSnapshot = jumpBackStack.popLast() else {
            showNotification(AppUILanguage.saved().text(.noEarlierReadingPosition))
            return
        }

        searchController?.markReaderNavigated()
        cancelPendingRestore()
        let current = snapshot()
        if let current {
            jumpForwardStack.append(current)
            trimJumpStacks()
        }

        restore(targetSnapshot)
        scheduleReadingPositionReport(userNavigated: current.map { !isSameJumpLocation($0, targetSnapshot) } ?? true)
    }

    func vimJumpForward() {
        guard let targetSnapshot = jumpForwardStack.popLast() else {
            showNotification(AppUILanguage.saved().text(.noLaterReadingPosition))
            return
        }

        searchController?.markReaderNavigated()
        cancelPendingRestore()
        let current = snapshot()
        if let current {
            jumpBackStack.append(current)
            trimJumpStacks()
        }

        restore(targetSnapshot)
        scheduleReadingPositionReport(userNavigated: current.map { !isSameJumpLocation($0, targetSnapshot) } ?? true)
    }
}
