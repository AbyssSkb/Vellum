@preconcurrency import AppKit
import PDFKit
extension VellumPDFView {
    func vimScroll(x: CGFloat, y: CGFloat) {
        completePendingRestoreBeforeUserInteraction()
        stopZoomState()
        guard let scrollView = pdfScrollView else { return }
        searchController?.markReaderNavigated()
        cancelPendingRestore()
        let clipView = scrollView.contentView
        let documentSize = scrollView.documentView?.bounds.size ?? .zero
        let maxX = max(0, documentSize.width - clipView.bounds.width)
        let verticalRange = verticalScrollRange(in: scrollView)
        let origin = animationState.scrollTargetOrigin ?? clipView.bounds.origin
        var next = NSPoint(
            x: ScrollGeometry.nextCoordinate(
                origin: origin.x,
                delta: x,
                contentLength: documentSize.width,
                viewportLength: clipView.bounds.width,
                maxValue: maxX
            ),
            y: ScrollGeometry.nextCoordinate(
                origin: origin.y,
                delta: y,
                contentLength: documentSize.height,
                viewportLength: clipView.bounds.height,
                maxValue: verticalRange.upperBound
            )
        )
        if y != 0, documentSize.height > clipView.bounds.height {
            next.y = max(verticalRange.lowerBound, next.y)
        }
        animationState.scrollTargetOrigin = next
        ensureScrollAnimation(in: scrollView)
    }

    func vimMoveByPage(_ delta: Int) {
        completePendingRestoreBeforeUserInteraction()
        guard let document,
              let pageState = currentPageState(),
              let targetPage = document.page(at: pageState.pageIndex + delta) else { return }
        let previous = readingDestination()

        searchController?.markReaderNavigated()
        cancelPendingRestore()
        stopScrollAnimation()
        stopZoomState()

        let sourceGeometry = PDFPageDisplayGeometry(page: pageState.page, box: displayBox)
        let targetGeometry = PDFPageDisplayGeometry(page: targetPage, box: displayBox)
        let sourcePoint = sourceGeometry.point(forPagePoint: pageState.pointOnPage)
        let xRatio = sourceGeometry.bounds.width > 0 ? sourcePoint.x / sourceGeometry.bounds.width : 0.5
        let yRatio = sourceGeometry.bounds.height > 0 ? sourcePoint.y / sourceGeometry.bounds.height : 0.5
        let targetPoint = targetGeometry.pagePoint(forDisplayPoint: NSPoint(
            x: targetGeometry.bounds.width * min(max(xRatio, 0), 1),
            y: targetGeometry.bounds.height * min(max(yRatio, 0), 1)
        ))
        let destination = PDFDestination(page: targetPage, at: targetPoint)

        go(to: destination)
        centerBothAxes(on: destination)
        let generation = restoreGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.restoreGeneration == generation else { return }
            self.centerBothAxes(on: destination)
            self.scheduleReadingPositionReport(userNavigated: self.readingPositionChanged(from: previous))
        }
    }
}
