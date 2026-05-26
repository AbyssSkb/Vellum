@preconcurrency import AppKit
import PDFKit
extension VellumPDFView {
    func vimScroll(x: CGFloat, y: CGFloat) {
        guard let scrollView = pdfScrollView else { return }
        cancelPendingRestore()
        let clipView = scrollView.contentView
        let documentSize = scrollView.documentView?.bounds.size ?? .zero
        let maxX = max(0, documentSize.width - clipView.bounds.width)
        let maxY = max(0, documentSize.height - clipView.bounds.height)
        let origin = scrollTargetOrigin ?? clipView.bounds.origin
        let next = NSPoint(
            x: nextScrollCoordinate(
                origin: origin.x,
                delta: x,
                contentLength: documentSize.width,
                viewportLength: clipView.bounds.width,
                maxValue: maxX
            ),
            y: nextScrollCoordinate(
                origin: origin.y,
                delta: y,
                contentLength: documentSize.height,
                viewportLength: clipView.bounds.height,
                maxValue: maxY
            )
        )
        scrollTargetOrigin = next
        ensureScrollAnimation(in: scrollView)
    }

    func vimMoveByPage(_ delta: Int) {
        guard let document,
              let pageState = currentPageState(),
              let targetPage = document.page(at: pageState.pageIndex + delta) else { return }

        cancelPendingRestore()
        stopScrollAnimation()
        stopZoomState()

        let targetBounds = targetPage.bounds(for: displayBox)
        let yRatio = pageState.pageBounds.height == 0
            ? 0
            : (pageState.pointOnPage.y - pageState.pageBounds.minY) / pageState.pageBounds.height
        let targetY = targetBounds.minY + targetBounds.height * min(max(yRatio, 0), 1)
        let targetPoint = NSPoint(x: targetBounds.midX, y: targetY)

        go(to: PDFDestination(page: targetPage, at: targetPoint))
        DispatchQueue.main.async { [weak self] in
            self?.centerVertically(on: PDFDestination(page: targetPage, at: targetPoint))
        }
    }
}
