@preconcurrency import AppKit
import PDFKit

extension VellumPDFView {
    func vimZoom(by factor: CGFloat) {
        completePendingRestoreBeforeUserInteraction()
        let baseScale = animationState.zoomTargetScale ?? scaleFactor
        vimZoom(to: baseScale * factor)
    }

    func vimZoom(to targetScale: CGFloat) {
        completePendingRestoreBeforeUserInteraction()
        cancelPendingRestore()
        stopScrollAnimation()
        animationState.zoomPageFitPhase = nil
        autoScales = false
        prepareZoomAnchor()
        animationState.zoomTargetScale = min(max(targetScale, minimumZoomScale), maximumZoomScale)
        ensureZoomAnimation()
    }

    func vimZoomToFit() {
        completePendingRestoreBeforeUserInteraction()
        cancelPendingRestore()
        stopScrollAnimation()
        animationState.zoomPageFitPhase = nil
        guard let anchor = centerDestination() ?? currentDestination,
              let page = anchor.page,
              let fitScale = widthFitScale(for: page) else { return }
        let pageCenter = convert(pageCenterDestination(for: page).point, from: page)
        let anchorPoint = convert(anchor.point, from: page)
        animationState.zoomAnchor = PDFDestination(
            page: page, at: convert(NSPoint(x: pageCenter.x, y: anchorPoint.y), to: page)
        )
        animationState.zoomTargetScale = min(max(fitScale, minimumZoomScale), maximumZoomScale)
        ensureZoomAnimation()
    }

    func vimZoomToPageFit() {
        completePendingRestoreBeforeUserInteraction()
        cancelPendingRestore()
        stopScrollAnimation()
        guard let scrollView = pdfScrollView else { return }
        func bottomIsPinned(_ page: PDFPage) -> Bool {
            guard let bottom = pageEdgeOrigin(for: page, edge: .bottom, in: scrollView) else { return false }
            return abs(scrollView.contentView.bounds.origin.y - bottom) < 0.5
        }
        let lastPage = document.flatMap { $0.page(at: $0.pageCount - 1) }
        // A short final page can be pinned below the viewport center after G.
        guard let page = lastPage.flatMap({ bottomIsPinned($0) ? $0 : nil }) ?? currentPageState()?.page else { return }
        let phase: ReaderAnimationState.PageFitPhase = bottomIsPinned(page) ? .bottom : .top
        guard let pageFitScale = pageFitScale(for: page) else { return }
        animationState.zoomAnchor = pageCenterDestination(for: page)
        animationState.zoomPageFitPhase = phase
        animationState.zoomTargetScale = min(max(pageFitScale, minimumZoomScale), maximumZoomScale)
        ensureZoomAnimation()
    }
}
