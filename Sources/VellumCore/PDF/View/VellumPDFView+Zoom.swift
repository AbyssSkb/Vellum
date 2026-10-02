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
        autoScales = false
        prepareZoomAnchor()
        animationState.zoomTargetScale = min(max(targetScale, minimumZoomScale), maximumZoomScale)
        ensureZoomAnimation()
    }

    func vimZoomToFit() {
        completePendingRestoreBeforeUserInteraction()
        cancelPendingRestore()
        stopScrollAnimation()
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
        guard let pageState = currentPageState(),
              let pageFitScale = pageFitScale(for: pageState.page) else { return }

        animationState.zoomAnchor = pageCenterDestination(for: pageState.page)
        animationState.zoomTargetScale = min(max(pageFitScale, minimumZoomScale), maximumZoomScale)
        ensureZoomAnimation()
    }
}
