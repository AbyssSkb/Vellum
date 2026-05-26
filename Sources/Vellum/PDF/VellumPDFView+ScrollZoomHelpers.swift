@preconcurrency import AppKit
import PDFKit

extension VellumPDFView {
    func currentHorizontalOrigin() -> CGFloat? {
        pdfScrollView?.contentView.bounds.origin.x
    }

    func restoreHorizontalOrigin(_ originX: CGFloat?) {
        guard let originX, let scrollView = pdfScrollView else { return }

        let clipView = scrollView.contentView
        let documentSize = scrollView.documentView?.bounds.size ?? .zero
        let maxX = max(0, documentSize.width - clipView.bounds.width)
        let clampedX = ScrollGeometry.restoredCoordinate(
            origin: originX,
            contentLength: documentSize.width,
            viewportLength: clipView.bounds.width,
            maxValue: maxX
        )

        clipView.scroll(to: NSPoint(x: clampedX, y: clipView.bounds.origin.y))
        scrollView.reflectScrolledClipView(clipView)
    }

    func ensureScrollAnimation(in scrollView: NSScrollView) {
        guard !animationState.hasActiveScrollTimer else { return }

        animationState.lastScrollTick = Date.timeIntervalSinceReferenceDate
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self, weak scrollView] timer in
            guard let self, let scrollView else {
                timer.invalidate()
                return
            }

            MainActor.assumeIsolated {
                self.stepScrollAnimation(in: scrollView)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationState.scrollTimer = timer
    }

    func stepScrollAnimation(in scrollView: NSScrollView) {
        guard let target = animationState.scrollTargetOrigin else {
            stopScrollAnimation()
            return
        }

        let now = Date.timeIntervalSinceReferenceDate
        let deltaTime = min(max(now - animationState.lastScrollTick, 1.0 / 240.0), 1.0 / 30.0)
        animationState.lastScrollTick = now

        let clipView = scrollView.contentView
        let origin = clipView.bounds.origin
        let deltaX = target.x - origin.x
        let deltaY = target.y - origin.y

        if abs(deltaX) < 0.45, abs(deltaY) < 0.45 {
            clipView.scroll(to: target)
            scrollView.reflectScrolledClipView(clipView)
            stopScrollAnimation()
            return
        }

        let progress = 1 - CGFloat(exp(-deltaTime / 0.055))
        let next = NSPoint(
            x: origin.x + deltaX * progress,
            y: origin.y + deltaY * progress
        )
        clipView.scroll(to: next)
        scrollView.reflectScrolledClipView(clipView)
    }

    func stopScrollAnimation() {
        animationState.clearScroll()
    }

    func prepareZoomAnchor() {
        if animationState.zoomAnchor == nil {
            animationState.zoomAnchor = centerDestination() ?? currentDestination
        }
    }

    func ensureZoomAnimation() {
        guard !animationState.hasActiveZoomTimer else { return }

        animationState.lastZoomTick = Date.timeIntervalSinceReferenceDate
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            MainActor.assumeIsolated {
                self.stepZoomAnimation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationState.zoomTimer = timer
    }

    func stepZoomAnimation() {
        guard let target = animationState.zoomTargetScale else {
            stopZoomState()
            return
        }

        let now = Date.timeIntervalSinceReferenceDate
        let deltaTime = min(max(now - animationState.lastZoomTick, 1.0 / 120.0), 1.0 / 30.0)
        animationState.lastZoomTick = now

        let current = scaleFactor
        let delta = target - current
        let threshold = max(0.001, target * 0.0008)

        if abs(delta) < threshold {
            applyZoomScale(target)
            stopZoomState()
            return
        }

        let progress = 1 - CGFloat(exp(-deltaTime / 0.11))
        applyZoomScale(current + delta * progress)
    }

    func applyZoomScale(_ scale: CGFloat) {
        autoScales = false
        scaleFactor = min(max(scale, minimumZoomScale), maximumZoomScale)
        layoutDocumentView()

        if let zoomAnchor = animationState.zoomAnchor {
            centerBothAxes(on: zoomAnchor)
        }
    }

    func stopZoomState() {
        animationState.clearZoom()
    }

    func cancelPendingRestore() {
        restoreGeneration += 1
    }

    @discardableResult
    func applyWidthFitScaleNow(for page: PDFPage? = nil) -> Bool {
        guard let fitScale = widthFitScale(for: page) else { return false }

        autoScales = false
        scaleFactor = fitScale
        layoutDocumentView()
        needsDisplay = true
        return true
    }

    func widthFitScale(for explicitPage: PDFPage? = nil) -> CGFloat? {
        guard let page = explicitPage ?? currentPage ?? currentDestination?.page ?? document?.page(at: 0),
              let viewportSize = fitViewportSize(),
              let pageSize = displaySize(for: page) else { return nil }

        return ZoomGeometry.widthFitScale(
            viewportSize: viewportSize,
            pageSize: pageSize,
            minimum: minimumZoomScale,
            maximum: maximumZoomScale
        )
    }

    func pageFitScale(for page: PDFPage) -> CGFloat? {
        guard let viewportSize = fitViewportSize(),
              let pageSize = displaySize(for: page) else { return nil }

        return ZoomGeometry.pageFitScale(
            viewportSize: viewportSize,
            pageSize: pageSize,
            minimum: minimumZoomScale,
            maximum: maximumZoomScale
        )
    }

    func fitViewportSize() -> NSSize? {
        guard window != nil, let scrollView = pdfScrollView else { return nil }

        layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()

        let viewportSize = scrollView.contentView.frame.size
        guard viewportSize.width > 100, viewportSize.height > 100 else { return nil }

        return viewportSize
    }

    func displaySize(for page: PDFPage) -> NSSize? {
        ZoomGeometry.displaySize(bounds: page.bounds(for: displayBox), rotation: page.rotation)
    }

    func clampedScale(_ scale: CGFloat) -> CGFloat {
        ZoomGeometry.clampedScale(scale, minimum: minimumZoomScale, maximum: maximumZoomScale)
    }

    func isSameViewportSize(_ lhs: NSSize, _ rhs: NSSize) -> Bool {
        ZoomGeometry.isSameViewportSize(lhs, rhs)
    }

    func pageCenterDestination(for page: PDFPage) -> PDFDestination {
        let bounds = page.bounds(for: displayBox)
        return PDFDestination(page: page, at: NSPoint(x: bounds.midX, y: bounds.midY))
    }

    func centerDestination() -> PDFDestination? {
        guard let scrollView = pdfScrollView else { return currentDestination }

        let clipView = scrollView.contentView
        let visibleCenter = NSPoint(x: clipView.bounds.midX, y: clipView.bounds.midY)
        let pointInPDFView = convert(visibleCenter, from: clipView)

        guard let page = page(for: pointInPDFView, nearest: true) else {
            return currentDestination
        }

        return PDFDestination(page: page, at: convert(pointInPDFView, to: page))
    }

    struct PageState {
        var page: PDFPage
        var pageIndex: Int
        var pointOnPage: NSPoint
        var pageBounds: NSRect
    }

    func currentPageState() -> PageState? {
        guard let document,
              let scrollView = pdfScrollView else { return nil }

        let clipView = scrollView.contentView
        let visibleCenter = NSPoint(x: clipView.bounds.midX, y: clipView.bounds.midY)
        let pointInPDFView = convert(visibleCenter, from: clipView)

        guard let page = page(for: pointInPDFView, nearest: true) ?? currentPage else { return nil }

        return PageState(
            page: page,
            pageIndex: document.index(for: page),
            pointOnPage: convert(pointInPDFView, to: page),
            pageBounds: page.bounds(for: displayBox)
        )
    }

    func topDestination(for page: PDFPage) -> PDFDestination {
        let bounds = page.bounds(for: displayBox)
        return PDFDestination(page: page, at: NSPoint(x: bounds.midX, y: bounds.maxY))
    }

    func centerVertically(on destination: PDFDestination) {
        guard let page = destination.page,
              let scrollView = pdfScrollView,
              let documentView = scrollView.documentView else {
            go(to: destination)
            return
        }

        let clipView = scrollView.contentView
        let pointInPDFView = convert(destination.point, from: page)
        let pointInDocument = convert(pointInPDFView, to: documentView)
        let documentSize = documentView.bounds.size
        let maxY = max(0, documentSize.height - clipView.bounds.height)
        let currentOrigin = clipView.bounds.origin
        let next = NSPoint(
            x: currentOrigin.x,
            y: ScrollGeometry.centeredCoordinate(
                point: pointInDocument.y,
                currentOrigin: currentOrigin.y,
                contentLength: documentSize.height,
                viewportLength: clipView.bounds.height,
                maxValue: maxY
            )
        )

        clipView.scroll(to: next)
        scrollView.reflectScrolledClipView(clipView)
    }

    func centerBothAxes(on destination: PDFDestination) {
        guard let page = destination.page,
              let scrollView = pdfScrollView,
              let documentView = scrollView.documentView else {
            go(to: destination)
            return
        }

        let clipView = scrollView.contentView
        let pointInPDFView = convert(destination.point, from: page)
        let pointInDocument = convert(pointInPDFView, to: documentView)
        let documentSize = documentView.bounds.size
        let maxX = max(0, documentSize.width - clipView.bounds.width)
        let maxY = max(0, documentSize.height - clipView.bounds.height)
        let currentOrigin = clipView.bounds.origin
        let next = NSPoint(
            x: ScrollGeometry.centeredCoordinate(
                point: pointInDocument.x,
                currentOrigin: currentOrigin.x,
                contentLength: documentSize.width,
                viewportLength: clipView.bounds.width,
                maxValue: maxX
            ),
            y: ScrollGeometry.centeredCoordinate(
                point: pointInDocument.y,
                currentOrigin: currentOrigin.y,
                contentLength: documentSize.height,
                viewportLength: clipView.bounds.height,
                maxValue: maxY
            )
        )

        clipView.scroll(to: next)
        scrollView.reflectScrolledClipView(clipView)
    }

    enum VerticalEdge {
        case top
        case bottom
    }

    func scrollToDocumentEdge(_ edge: VerticalEdge) {
        guard let scrollView = pdfScrollView else { return }

        let clipView = scrollView.contentView
        let documentSize = scrollView.documentView?.bounds.size ?? .zero
        let maxY = max(0, documentSize.height - clipView.bounds.height)
        let currentOrigin = clipView.bounds.origin
        let geometryEdge: ScrollGeometry.VerticalEdge = edge == .top ? .top : .bottom
        let nextY = ScrollGeometry.verticalEdgeCoordinate(
            edge: geometryEdge,
            isFlipped: scrollView.documentView?.isFlipped == true,
            maxValue: maxY
        )

        clipView.scroll(to: NSPoint(x: currentOrigin.x, y: nextY))
        scrollView.reflectScrolledClipView(clipView)
    }

    var minimumZoomScale: CGFloat {
        minScaleFactor > 0 ? minScaleFactor : 0.1
    }

    var maximumZoomScale: CGFloat {
        maxScaleFactor > minimumZoomScale ? maxScaleFactor : 8
    }

    var pdfScrollView: NSScrollView? {
        findScrollView(in: self)
    }

    func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) {
                return scrollView
            }
        }

        return nil
    }
}
