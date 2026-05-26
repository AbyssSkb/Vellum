@preconcurrency import AppKit
import PDFKit

extension VellumPDFView {
    func vimGoToFirstPage() {
        cancelPendingRestore()
        recordJumpSource()
        stopScrollAnimation()
        stopZoomState()
        goToFirstPage(nil)
        DispatchQueue.main.async { [weak self] in
            self?.scrollToDocumentEdge(.top)
        }
    }

    func vimGoToLastPage() {
        cancelPendingRestore()
        recordJumpSource()
        stopScrollAnimation()
        stopZoomState()
        goToLastPage(nil)
        DispatchQueue.main.async { [weak self] in
            self?.scrollToDocumentEdge(.bottom)
        }
    }

    func vimGoToPage(_ pageNumber: Int) {
        guard let document, document.pageCount > 0 else { return }

        let pageIndex = min(max(pageNumber - 1, 0), document.pageCount - 1)
        guard let page = document.page(at: pageIndex) else { return }

        cancelPendingRestore()
        recordJumpSource()
        stopScrollAnimation()
        stopZoomState()

        let destination = topDestination(for: page)
        go(to: destination)
        DispatchQueue.main.async { [weak self] in
            self?.go(to: destination)
        }
    }

    func vimGoToDestination(_ destination: PDFDestination) {
        let horizontalOrigin = currentHorizontalOrigin()

        cancelPendingRestore()
        recordJumpSource()
        stopScrollAnimation()
        stopZoomState()

        go(to: destination)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.go(to: destination)
            self.restoreHorizontalOrigin(horizontalOrigin)

            DispatchQueue.main.async { [weak self] in
                self?.restoreHorizontalOrigin(horizontalOrigin)
            }
        }
    }

    func vimJumpBack() {
        guard let targetSnapshot = jumpBackStack.popLast() else { return }

        cancelPendingRestore()
        if let current = self.snapshot() {
            jumpForwardStack.append(current)
            trimJumpStacks()
        }

        restore(targetSnapshot)
    }

    func vimJumpForward() {
        guard let targetSnapshot = jumpForwardStack.popLast() else { return }

        cancelPendingRestore()
        if let current = self.snapshot() {
            jumpBackStack.append(current)
            trimJumpStacks()
        }

        restore(targetSnapshot)
    }
}
