@preconcurrency import AppKit
import PDFKit

extension VellumPDFView {
    func vimZoom(by factor: CGFloat) {
        cancelPendingRestore()
        let baseScale = animationState.zoomTargetScale ?? scaleFactor
        vimZoom(to: baseScale * factor)
    }

    func vimZoom(to targetScale: CGFloat) {
        cancelPendingRestore()
        stopScrollAnimation()
        autoScales = false
        prepareZoomAnchor()
        animationState.zoomTargetScale = min(max(targetScale, minimumZoomScale), maximumZoomScale)
        ensureZoomAnimation()
    }

    func vimZoomToFit() {
        cancelPendingRestore()
        stopScrollAnimation()
        guard let fitScale = widthFitScale() else { return }
        animationState.zoomAnchor = centerDestination() ?? currentDestination
        animationState.zoomTargetScale = min(max(fitScale, minimumZoomScale), maximumZoomScale)
        ensureZoomAnimation()
    }

    func vimZoomToPageFit() {
        cancelPendingRestore()
        stopScrollAnimation()
        guard let pageState = currentPageState(),
              let pageFitScale = pageFitScale(for: pageState.page) else { return }

        animationState.zoomAnchor = pageCenterDestination(for: pageState.page)
        animationState.zoomTargetScale = min(max(pageFitScale, minimumZoomScale), maximumZoomScale)
        ensureZoomAnimation()
    }
}
