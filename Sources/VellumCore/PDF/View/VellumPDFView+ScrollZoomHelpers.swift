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
        guard let requestedTarget = animationState.scrollTargetOrigin else {
            stopScrollAnimation()
            return
        }

        let now = Date.timeIntervalSinceReferenceDate
        let deltaTime = AnimationGeometry.clampedDeltaTime(
            from: animationState.lastScrollTick,
            to: now,
            minimum: 1.0 / 240.0,
            maximum: 1.0 / 30.0
        )
        animationState.lastScrollTick = now

        let clipView = scrollView.contentView
        let documentBounds = scrollView.documentView?.bounds ?? .zero
        let verticalRange = verticalScrollRange(in: scrollView)
        func constrainedOrigin(_ proposed: NSPoint) -> NSPoint {
            let native = clipView.constrainBoundsRect(NSRect(origin: proposed, size: clipView.bounds.size)).origin
            // Native constraints round to pixels, which can stall an animation short of a fractional target.
            return NSPoint(
                x: documentBounds.width > clipView.bounds.width
                    ? min(max(proposed.x, documentBounds.minX), documentBounds.maxX - clipView.bounds.width) : native.x,
                y: min(max(proposed.y, verticalRange.lowerBound), verticalRange.upperBound)
            )
        }
        let target = constrainedOrigin(requestedTarget)
        animationState.scrollTargetOrigin = target
        let origin = clipView.bounds.origin

        if AnimationGeometry.isNearTarget(current: origin.x, target: target.x, threshold: 0.45),
           AnimationGeometry.isNearTarget(current: origin.y, target: target.y, threshold: 0.45) {
            clipView.scroll(to: target)
            scrollView.reflectScrolledClipView(clipView)
            stopScrollAnimation()
            return
        }

        let progress = AnimationGeometry.exponentialProgress(deltaTime: deltaTime, timeConstant: 0.055)
        let next = NSPoint(
            x: AnimationGeometry.nextValue(current: origin.x, target: target.x, progress: progress),
            y: AnimationGeometry.nextValue(current: origin.y, target: target.y, progress: progress)
        )
        clipView.scroll(to: constrainedOrigin(next))
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
        let deltaTime = AnimationGeometry.clampedDeltaTime(
            from: animationState.lastZoomTick,
            to: now,
            minimum: 1.0 / 120.0,
            maximum: 1.0 / 30.0
        )
        animationState.lastZoomTick = now

        if animationState.zoomPageFitPhase == .aligningTop {
            guard let page = animationState.zoomAnchor?.page,
                  let scrollView = pdfScrollView,
                  let targetY = pageEdgeOrigin(for: page, edge: .top, in: scrollView) else {
                stopZoomState()
                return
            }
            let clipView = scrollView.contentView
            let origin = clipView.bounds.origin
            let finished = AnimationGeometry.isNearTarget(current: origin.y, target: targetY, threshold: 0.45)
            let progress = AnimationGeometry.exponentialProgress(deltaTime: deltaTime, timeConstant: 0.11)
            clipView.scroll(to: NSPoint(x: origin.x, y: finished ? targetY
                : AnimationGeometry.nextValue(current: origin.y, target: targetY, progress: progress)))
            scrollView.reflectScrolledClipView(clipView)
            if finished { stopZoomState() }
            return
        }

        let current = scaleFactor
        let threshold = max(0.001, target * 0.0008)

        if AnimationGeometry.isNearTarget(current: current, target: target, threshold: threshold) {
            applyZoomScale(target)
            // Keep one final tick so PDFKit's deferred magnification layout finishes before anchoring.
            if current != target { return }
            if animationState.zoomPageFitPhase == .bottom {
                animationState.zoomPageFitPhase = .aligningTop
            } else {
                stopZoomState()
            }
            return
        }

        let progress = AnimationGeometry.exponentialProgress(deltaTime: deltaTime, timeConstant: 0.11)
        applyZoomScale(AnimationGeometry.nextValue(current: current, target: target, progress: progress))
    }

    func applyZoomScale(_ scale: CGFloat) {
        autoScales = false
        let nextScale = clampedScale(scale)
        if scaleFactor != nextScale {
            // PDFKit updates magnification and page tiling when scaleFactor changes.
            scaleFactor = nextScale
        }

        if let zoomAnchor = animationState.zoomAnchor {
            let phase = animationState.zoomPageFitPhase
            centerBothAxes(on: zoomAnchor, pageEdge: phase == .bottom ? .bottom : phase == .top ? .top : nil)
        }
    }

    func stopZoomState() {
        animationState.clearZoom()
    }

    func cancelPendingRestore(cancelNativeScroll: Bool = true) {
        if cancelNativeScroll, let scrollView = pdfScrollView {
            PDFNativeScrollBoundsConstraint.cancel(in: scrollView)
        }
        restoreGeneration += 1
        pendingRestoreAction = nil
        for overlay in subviews.compactMap({ $0 as? PageOverviewOverlayView }) where overlay.dismissed {
            overlay.dismiss(animated: false)
        }
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
            pointOnPage: convert(pointInPDFView, to: page)
        )
    }

    func topDestination(for page: PDFPage) -> PDFDestination {
        let geometry = PDFPageDisplayGeometry(page: page, box: displayBox)
        let point = geometry.pagePoint(forDisplayPoint: NSPoint(x: geometry.bounds.midX, y: geometry.bounds.maxY))
        return PDFDestination(page: page, at: point)
    }

    func centerBothAxes(on destination: PDFDestination, pageEdge: VerticalEdge? = nil) {
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
        let edgeOrigin = pageEdge.flatMap { pageEdgeOrigin(for: page, edge: $0, in: scrollView) }
        let next = NSPoint(
            x: ScrollGeometry.centeredCoordinate(
                point: pointInDocument.x,
                currentOrigin: currentOrigin.x,
                contentLength: documentSize.width,
                viewportLength: clipView.bounds.width,
                maxValue: maxX
            ),
            y: edgeOrigin ?? ScrollGeometry.centeredCoordinate(
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

    func pageEdgeOrigin(for page: PDFPage, edge: VerticalEdge, in scrollView: NSScrollView) -> CGFloat? {
        guard let documentView = scrollView.documentView else { return nil }
        let paper = convert(convert(page.bounds(for: displayBox), from: page), to: documentView)
        return (edge == .top) == documentView.isFlipped
            ? paper.minY : paper.maxY - scrollView.contentView.bounds.height
    }

    func verticalScrollRange(in scrollView: NSScrollView) -> ClosedRange<CGFloat> {
        let clipView = scrollView.contentView
        let documentBounds = scrollView.documentView?.bounds ?? .zero
        let minimum = documentBounds.minY
        let maximum = max(minimum, documentBounds.maxY - clipView.bounds.height)
        guard let documentView = scrollView.documentView,
              let document,
              let firstPage = document.page(at: 0),
              let lastPage = document.page(at: document.pageCount - 1) else { return minimum...maximum }

        let firstPaper = convert(convert(firstPage.bounds(for: displayBox), from: firstPage), to: documentView)
        let lastPaper = convert(convert(lastPage.bounds(for: displayBox), from: lastPage), to: documentView)
        let top = documentView.isFlipped ? firstPaper.minY : firstPaper.maxY - clipView.bounds.height
        let bottom = documentView.isFlipped ? lastPaper.maxY - clipView.bounds.height : lastPaper.minY
        let origin = clipView.bounds.origin.y
        // A document shorter than the viewport is already fully visible.
        guard documentView.isFlipped ? top < bottom : bottom < top else {
            let pinned = min(max(origin, min(top, bottom)), max(top, bottom))
            return pinned...pinned
        }
        // Preserve a fitted final page's top alignment without permitting any further overscroll.
        if lastPaper.minY >= origin - 0.5, lastPaper.maxY <= origin + clipView.bounds.height + 0.5 {
            return documentView.isFlipped ? top...max(bottom, origin) : min(bottom, origin)...top
        }
        return min(top, bottom)...max(top, bottom)
    }

    func scrollToDocumentEdge(_ edge: VerticalEdge) {
        guard let scrollView = pdfScrollView,
              let document,
              let page = document.page(at: edge == .top ? 0 : document.pageCount - 1),
              let nextY = pageEdgeOrigin(for: page, edge: edge, in: scrollView) else { return }

        let clipView = scrollView.contentView
        let currentOrigin = clipView.bounds.origin

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
