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
        var nextX = ScrollGeometry.nextCoordinate(
            origin: origin.x,
            delta: x,
            contentLength: documentSize.width,
            viewportLength: clipView.bounds.width,
            maxValue: maxX
        )
        if x != 0, let documentView = scrollView.documentView,
           let document, let current = currentPageState() {
            func paperBounds(_ page: PDFPage) -> NSRect {
                convert(convert(page.bounds(for: displayBox), from: page), to: documentView)
            }
            var papers = [paperBounds(current.page)]
            for direction in [-1, 1] {
                var index = current.pageIndex + direction
                while index >= 0, index < document.pageCount, let page = document.page(at: index) {
                    let paper = paperBounds(page)
                    guard paper.maxY > clipView.bounds.minY, paper.minY < clipView.bounds.maxY else { break }
                    papers.append(paper)
                    index += direction
                }
            }
            let ranges = papers.map { paper in
                if paper.width <= clipView.bounds.width + 0.5 {
                    let centered = paper.midX - clipView.bounds.width / 2
                    return centered...centered
                }
                return paper.minX...(paper.maxX - clipView.bounds.width)
            }
            if let minimum = ranges.map(\.lowerBound).min(), let maximum = ranges.map(\.upperBound).max() {
                // A prior page may leave the viewport outside the visible pages' range.
                nextX = x < 0 ? max(nextX, min(origin.x, minimum)) : min(nextX, max(origin.x, maximum))
            }
        }
        // Keyboard deltas use positive y for up; PDFKit's document coordinates can be flipped.
        let verticalDelta = scrollView.documentView?.isFlipped == true ? -y : y
        let next = NSPoint(
            x: nextX,
            y: y == 0 ? origin.y : min(max(origin.y + verticalDelta, verticalRange.lowerBound), verticalRange.upperBound)
        )
        animationState.scrollTargetOrigin = next
        ensureScrollAnimation(in: scrollView)
    }

    func vimMoveByPage(_ delta: Int) {
        completePendingRestoreBeforeUserInteraction()
        guard let document,
              let pageState = currentPageState() else { return }
        let targetIndex = pageState.pageIndex + min(max(delta, -pageState.pageIndex), document.pageCount - 1 - pageState.pageIndex)
        guard targetIndex != pageState.pageIndex,
              let targetPage = document.page(at: targetIndex) else { return }
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
