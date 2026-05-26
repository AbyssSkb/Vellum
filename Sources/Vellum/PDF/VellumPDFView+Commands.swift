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

    func vimHighlightSelection(color: NSColor) {
        guard let selection = currentSelection else {
            NSSound.beep()
            return
        }

        let annotations = addHighlightAnnotations(for: selection, color: color)
        guard !annotations.isEmpty else {
            NSSound.beep()
            return
        }

        clearSelection()
        textSelectionNavigationState = nil
        needsDisplay = true
        persistAnnotationsIfPossible()
    }

    @discardableResult
    func addHighlightAnnotations(for selection: PDFSelection, color: NSColor) -> [PDFAnnotation] {
        let lineSelections = selection.selectionsByLine()
        let selections = lineSelections.isEmpty ? [selection] : lineSelections
        var annotations: [PDFAnnotation] = []
        let groupID = UUID().uuidString

        for lineSelection in selections {
            for page in lineSelection.pages {
                guard let bounds = HighlightGeometry.tightBounds(for: lineSelection, on: page) else { continue }

                let preservedExplanation = existingAIExplanation(on: page, intersecting: [bounds])
                removeHighlightAnnotations(on: page, intersecting: bounds)

                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = color
                annotation.quadrilateralPoints = HighlightGeometry.quadrilateralPoints(for: bounds)
                HighlightAnnotationMetadata.setGroupID(groupID, for: annotation)
                if let preservedExplanation {
                    annotation.contents = AIExplanationAnnotation.encode(preservedExplanation)
                    annotation.userName = "Vellum AI"
                }
                annotation.shouldDisplay = true
                annotation.shouldPrint = true
                page.addAnnotation(annotation)
                annotations.append(annotation)
            }
        }

        return annotations
    }

    func vimDeleteHighlightsForSelection() -> Bool {
        guard let selection = currentSelection else { return false }

        let selectionsByPage = highlightSelectionBoundsByPage(for: selection)
        var didRemoveHighlight = false

        for pageSelection in selectionsByPage {
            didRemoveHighlight = removeHighlightAnnotations(
                on: pageSelection.page,
                intersecting: pageSelection.bounds
            ) || didRemoveHighlight
        }

        guard didRemoveHighlight else {
            NSSound.beep()
            return true
        }

        clearSelection()
        needsDisplay = true
        persistAnnotationsIfPossible()
        return true
    }

    func vimExplainSelectedHighlight() {
        guard let selection = currentSelection,
              let selectedText = selection.string?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty else {
            showAIMessage(AIExplanationError.noSelection.localizedDescription)
            NSSound.beep()
            return
        }

        let anchor = selectionPopoverRect(for: selection)
        let targetAnnotations = highlightedAnnotations(intersecting: selection)

        let configuration: AIConfiguration
        do {
            configuration = try AIConfiguration.current()
        } catch {
            showAIMessage(error.localizedDescription)
            NSSound.beep()
            return
        }

        guard let context = AIExplanationContextBuilder.context(
            for: selection,
            selectedText: selectedText,
            document: document
        ) else {
            showAIMessage(AIExplanationError.noSelection.localizedDescription)
            NSSound.beep()
            return
        }

        activeAIExplanationTask?.cancel()
        activeAISelection = selection.copy() as? PDFSelection ?? selection
        activeAIExistingAnnotations = targetAnnotations
        let popoverModel = showStreamingAIExplanationPopover(
            title: selectedText.aiPopoverTitle,
            at: anchor
        )

        let task = Task { @MainActor [weak self] in
            do {
                let explanation = try await AIExplanationClient.streamExplanation(
                    context: context,
                    configuration: configuration,
                    onChunk: { chunk in
                        popoverModel?.append(chunk)
                    }
                )
                guard let self else { return }

                for annotation in self.activeAIExistingAnnotations {
                    annotation.contents = AIExplanationAnnotation.encode(explanation)
                    annotation.userName = "Vellum AI"
                    annotation.modificationDate = Date()
                }

                if !self.activeAIExistingAnnotations.isEmpty {
                    self.needsDisplay = true
                    self.persistAnnotationsIfPossible()
                }
                popoverModel?.isStreaming = false
                self.activeAIExplanationTask = nil
            } catch {
                guard !Task.isCancelled else { return }
                self?.activeAIExplanationTask = nil
                popoverModel?.isStreaming = false
                popoverModel?.title = "AI request failed"
                popoverModel?.text = error.localizedDescription
                NSSound.beep()
            }
        }
        activeAIExplanationTask = task
    }

    func vimZoom(by factor: CGFloat) {
        cancelPendingRestore()
        let baseScale = zoomTargetScale ?? scaleFactor
        vimZoom(to: baseScale * factor)
    }

    func vimZoom(to targetScale: CGFloat) {
        cancelPendingRestore()
        stopScrollAnimation()
        autoScales = false
        prepareZoomAnchor()
        zoomTargetScale = min(max(targetScale, minimumZoomScale), maximumZoomScale)
        ensureZoomAnimation()
    }

    func vimZoomToFit() {
        cancelPendingRestore()
        stopScrollAnimation()
        guard let fitScale = widthFitScale() else { return }
        zoomAnchor = centerDestination() ?? currentDestination
        zoomTargetScale = min(max(fitScale, minimumZoomScale), maximumZoomScale)
        ensureZoomAnimation()
    }

    func vimZoomToPageFit() {
        cancelPendingRestore()
        stopScrollAnimation()
        guard let pageState = currentPageState(),
              let pageFitScale = pageFitScale(for: pageState.page) else { return }

        zoomAnchor = pageCenterDestination(for: pageState.page)
        zoomTargetScale = min(max(pageFitScale, minimumZoomScale), maximumZoomScale)
        ensureZoomAnimation()
    }

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

    func snapshot() -> ReaderSnapshot? {
        guard let document else { return nil }

        if let scrollView = pdfScrollView {
            let clipView = scrollView.contentView
            let visibleCenter = NSPoint(x: clipView.bounds.midX, y: clipView.bounds.midY)
            let pointInPDFView = convert(visibleCenter, from: clipView)

            if let page = page(for: pointInPDFView, nearest: true) {
                return ReaderSnapshot(
                    pageIndex: document.index(for: page),
                    pointOnPage: convert(pointInPDFView, to: page),
                    scrollOrigin: clipView.bounds.origin,
                    scaleFactor: scaleFactor,
                    autoScales: autoScales
                )
            }
        }

        guard let destination = currentDestination,
              let page = destination.page else { return nil }

        return ReaderSnapshot(
            pageIndex: document.index(for: page),
            pointOnPage: destination.point,
            scrollOrigin: nil,
            scaleFactor: scaleFactor,
            autoScales: autoScales
        )
    }

    func restore(_ snapshot: ReaderSnapshot?) {
        restoreGeneration += 1
        let generation = restoreGeneration
        stopScrollAnimation()
        stopZoomState()

        if snapshot == .initial {
            restoreInitialDocumentPosition(generation: generation)
            return
        }

        guard let snapshot, let document, let page = document.page(at: snapshot.pageIndex) else {
            _ = applyWidthFitScaleNow()
            return
        }

        autoScales = false
        if snapshot.autoScales {
            _ = applyWidthFitScaleNow()
        } else {
            scaleFactor = snapshot.scaleFactor
            layoutDocumentView()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.go(to: PDFDestination(page: page, at: snapshot.pointOnPage))
            self.restoreScrollOrigin(snapshot.scrollOrigin)

            DispatchQueue.main.async { [weak self] in
                self?.restoreScrollOrigin(snapshot.scrollOrigin)
            }
        }
    }

    func restoreInitialDocumentPosition(
        generation: Int,
        attemptsRemaining: Int = 30,
        stablePasses: Int = 0,
        lastViewportSize: NSSize? = nil
    ) {
        guard generation == restoreGeneration else { return }

        let viewportSize = fitViewportSize()
        let didFit = applyWidthFitScaleNow(for: document?.page(at: 0))
        if didFit {
            goToFirstPage(nil)
            scrollToDocumentEdge(.top)
        }

        let nextStablePasses: Int
        if didFit,
           let viewportSize,
           let lastViewportSize,
           isSameViewportSize(viewportSize, lastViewportSize) {
            nextStablePasses = stablePasses + 1
        } else {
            nextStablePasses = 0
        }

        guard attemptsRemaining > 0, (!didFit || nextStablePasses < 2) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.restoreInitialDocumentPosition(
                generation: generation,
                attemptsRemaining: attemptsRemaining - 1,
                stablePasses: nextStablePasses,
                lastViewportSize: viewportSize
            )
        }
    }

    func recordJumpSource() {
        guard let current = snapshot() else { return }

        if let last = jumpBackStack.last, isSameJumpLocation(last, current) {
            jumpForwardStack.removeAll()
            return
        }

        jumpBackStack.append(current)
        jumpForwardStack.removeAll()
        trimJumpStacks()
    }

    func trimJumpStacks() {
        if jumpBackStack.count > 100 {
            jumpBackStack.removeFirst(jumpBackStack.count - 100)
        }

        if jumpForwardStack.count > 100 {
            jumpForwardStack.removeFirst(jumpForwardStack.count - 100)
        }
    }

    func isSameJumpLocation(_ lhs: ReaderSnapshot, _ rhs: ReaderSnapshot) -> Bool {
        lhs.pageIndex == rhs.pageIndex
            && abs(lhs.pointOnPage.x - rhs.pointOnPage.x) < 2
            && abs(lhs.pointOnPage.y - rhs.pointOnPage.y) < 2
    }

    func restoreScrollOrigin(_ origin: NSPoint?) {
        guard let origin, let scrollView = pdfScrollView else { return }
        stopScrollAnimation()

        let clipView = scrollView.contentView
        let documentSize = scrollView.documentView?.bounds.size ?? .zero
        let maxX = max(0, documentSize.width - clipView.bounds.width)
        let maxY = max(0, documentSize.height - clipView.bounds.height)
        let clamped = NSPoint(
            x: restoredScrollCoordinate(
                origin: origin.x,
                contentLength: documentSize.width,
                viewportLength: clipView.bounds.width,
                maxValue: maxX
            ),
            y: restoredScrollCoordinate(
                origin: origin.y,
                contentLength: documentSize.height,
                viewportLength: clipView.bounds.height,
                maxValue: maxY
            )
        )

        clipView.scroll(to: clamped)
        scrollView.reflectScrolledClipView(clipView)
    }

    func persistAnnotationsIfPossible() {
        guard let document, let url = document.documentURL else { return }
        if !document.write(to: url) {
            NSSound.beep()
        }
    }

    @discardableResult
    func removeHighlightAnnotations(on page: PDFPage, intersecting bounds: NSRect) -> Bool {
        removeHighlightAnnotations(on: page, intersecting: [bounds])
    }

    @discardableResult
    func removeHighlightAnnotations(on page: PDFPage, intersecting selectionBounds: [NSRect]) -> Bool {
        let highlights = highlightAnnotationsToRemove(on: page, intersecting: selectionBounds)

        for annotation in highlights {
            page.removeAnnotation(annotation)
        }

        return !highlights.isEmpty
    }

    func highlightAnnotationsToRemove(on page: PDFPage, intersecting selectionBounds: [NSRect]) -> [PDFAnnotation] {
        let directlyHitHighlights = highlightAnnotations(on: page, intersecting: selectionBounds)
        var seen = Set<ObjectIdentifier>()
        var result: [PDFAnnotation] = []

        for annotation in directlyHitHighlights {
            for groupedAnnotation in highlightGroupAnnotations(for: annotation, on: page) {
                let identifier = ObjectIdentifier(groupedAnnotation)
                guard seen.insert(identifier).inserted else { continue }
                result.append(groupedAnnotation)
            }
        }

        return result
    }

    func highlightGroupAnnotations(for seed: PDFAnnotation, on page: PDFPage) -> [PDFAnnotation] {
        if let groupID = HighlightAnnotationMetadata.groupID(for: seed) {
            return page.annotations.filter { annotation in
                annotation.type == "Highlight"
                    && HighlightAnnotationMetadata.groupID(for: annotation) == groupID
            }
        }

        if let explanation = AIExplanationAnnotation.decode(seed.contents) {
            return explanationAnnotations(matching: explanation, on: page)
        }

        return legacyConnectedHighlightGroup(for: seed, on: page)
    }

    func legacyConnectedHighlightGroup(for seed: PDFAnnotation, on page: PDFPage) -> [PDFAnnotation] {
        let candidates = page.annotations.filter { annotation in
            annotation.type == "Highlight"
                && HighlightAnnotationMetadata.groupID(for: annotation) == nil
                && AIExplanationAnnotation.decode(annotation.contents) == nil
                && HighlightGeometry.colorsMatch(annotation.color, seed.color)
        }
        var result: [PDFAnnotation] = []
        var queue: [PDFAnnotation] = [seed]
        var seen = Set<ObjectIdentifier>()

        while let annotation = queue.popLast() {
            let identifier = ObjectIdentifier(annotation)
            guard seen.insert(identifier).inserted else { continue }
            result.append(annotation)

            for candidate in candidates where !seen.contains(ObjectIdentifier(candidate)) {
                if HighlightGeometry.annotationsAreConnected(annotation, candidate) {
                    queue.append(candidate)
                }
            }
        }

        return result
    }

    func existingAIExplanation(on page: PDFPage, intersecting selectionBounds: [NSRect]) -> String? {
        highlightAnnotations(on: page, intersecting: selectionBounds)
            .compactMap { AIExplanationAnnotation.decode($0.contents) }
            .first
    }

    func highlightedAnnotations(intersecting selection: PDFSelection) -> [PDFAnnotation] {
        let selectionsByPage = highlightSelectionBoundsByPage(for: selection)
        var seen = Set<ObjectIdentifier>()
        var annotations: [PDFAnnotation] = []

        for pageSelection in selectionsByPage {
            for annotation in highlightAnnotations(on: pageSelection.page, intersecting: pageSelection.bounds) {
                let identifier = ObjectIdentifier(annotation)
                guard seen.insert(identifier).inserted else { continue }
                annotations.append(annotation)
            }
        }

        return annotations
    }

    func highlightAnnotations(on page: PDFPage, intersecting selectionBounds: [NSRect]) -> [PDFAnnotation] {
        guard !selectionBounds.isEmpty else { return [] }

        return page.annotations.filter { annotation in
            annotation.type == "Highlight"
                && HighlightGeometry.regions(for: annotation).contains { highlightBounds in
                    selectionBounds.contains { selectedBounds in
                        HighlightGeometry.matches(annotationBounds: highlightBounds, selectionBounds: selectedBounds)
                    }
                }
        }
    }

    struct PageSelectionBounds {
        var page: PDFPage
        var bounds: [NSRect]
    }

    func highlightSelectionBoundsByPage(for selection: PDFSelection) -> [PageSelectionBounds] {
        let lineSelections = selection.selectionsByLine()
        let selections = lineSelections.isEmpty ? [selection] : lineSelections
        var result: [PageSelectionBounds] = []

        for lineSelection in selections {
            for page in lineSelection.pages {
                guard let bounds = HighlightGeometry.tightBounds(for: lineSelection, on: page) else { continue }

                if let index = result.firstIndex(where: { $0.page === page }) {
                    result[index].bounds.append(bounds)
                } else {
                    result.append(PageSelectionBounds(page: page, bounds: [bounds]))
                }
            }
        }

        return result
    }

    func currentHorizontalOrigin() -> CGFloat? {
        pdfScrollView?.contentView.bounds.origin.x
    }

    func restoreHorizontalOrigin(_ originX: CGFloat?) {
        guard let originX, let scrollView = pdfScrollView else { return }

        let clipView = scrollView.contentView
        let documentSize = scrollView.documentView?.bounds.size ?? .zero
        let maxX = max(0, documentSize.width - clipView.bounds.width)
        let clampedX = restoredScrollCoordinate(
            origin: originX,
            contentLength: documentSize.width,
            viewportLength: clipView.bounds.width,
            maxValue: maxX
        )

        clipView.scroll(to: NSPoint(x: clampedX, y: clipView.bounds.origin.y))
        scrollView.reflectScrolledClipView(clipView)
    }

    func ensureScrollAnimation(in scrollView: NSScrollView) {
        guard scrollTimer?.isValid != true else { return }

        lastScrollTick = Date.timeIntervalSinceReferenceDate
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
        scrollTimer = timer
    }

    func stepScrollAnimation(in scrollView: NSScrollView) {
        guard let target = scrollTargetOrigin else {
            stopScrollAnimation()
            return
        }

        let now = Date.timeIntervalSinceReferenceDate
        let deltaTime = min(max(now - lastScrollTick, 1.0 / 240.0), 1.0 / 30.0)
        lastScrollTick = now

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
        scrollTimer?.invalidate()
        scrollTimer = nil
        scrollTargetOrigin = nil
    }

    func prepareZoomAnchor() {
        if zoomAnchor == nil {
            zoomAnchor = centerDestination() ?? currentDestination
        }
    }

    func ensureZoomAnimation() {
        guard zoomTimer?.isValid != true else { return }

        lastZoomTick = Date.timeIntervalSinceReferenceDate
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
        zoomTimer = timer
    }

    func stepZoomAnimation() {
        guard let target = zoomTargetScale else {
            stopZoomState()
            return
        }

        let now = Date.timeIntervalSinceReferenceDate
        let deltaTime = min(max(now - lastZoomTick, 1.0 / 120.0), 1.0 / 30.0)
        lastZoomTick = now

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

        if let zoomAnchor {
            centerBothAxes(on: zoomAnchor)
        }
    }

    func stopZoomState() {
        zoomTimer?.invalidate()
        zoomTimer = nil
        zoomTargetScale = nil
        zoomAnchor = nil
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

        return clampedScale((viewportSize.width * 0.985) / pageSize.width)
    }

    func pageFitScale(for page: PDFPage) -> CGFloat? {
        guard let viewportSize = fitViewportSize(),
              let pageSize = displaySize(for: page) else { return nil }

        let widthScale = (viewportSize.width * 0.985) / pageSize.width
        let heightScale = (viewportSize.height * 0.985) / pageSize.height
        return clampedScale(min(widthScale, heightScale))
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
        let bounds = page.bounds(for: displayBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let normalizedRotation = ((page.rotation % 360) + 360) % 360
        if normalizedRotation == 90 || normalizedRotation == 270 {
            return NSSize(width: bounds.height, height: bounds.width)
        }

        return bounds.size
    }

    func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimumZoomScale), maximumZoomScale)
    }

    func isSameViewportSize(_ lhs: NSSize, _ rhs: NSSize) -> Bool {
        abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
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
            y: centeredScrollCoordinate(
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
            x: centeredScrollCoordinate(
                point: pointInDocument.x,
                currentOrigin: currentOrigin.x,
                contentLength: documentSize.width,
                viewportLength: clipView.bounds.width,
                maxValue: maxX
            ),
            y: centeredScrollCoordinate(
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

    func nextScrollCoordinate(
        origin: CGFloat,
        delta: CGFloat,
        contentLength: CGFloat,
        viewportLength: CGFloat,
        maxValue: CGFloat
    ) -> CGFloat {
        guard delta != 0 else { return origin }
        guard contentLength > viewportLength else { return origin }
        return min(max(0, origin + delta), maxValue)
    }

    func restoredScrollCoordinate(
        origin: CGFloat,
        contentLength: CGFloat,
        viewportLength: CGFloat,
        maxValue: CGFloat
    ) -> CGFloat {
        guard contentLength > viewportLength else { return origin }
        return min(max(0, origin), maxValue)
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
        let nextY: CGFloat

        if scrollView.documentView?.isFlipped == true {
            nextY = edge == .top ? 0 : maxY
        } else {
            nextY = edge == .top ? maxY : 0
        }

        clipView.scroll(to: NSPoint(x: currentOrigin.x, y: nextY))
        scrollView.reflectScrolledClipView(clipView)
    }

    func centeredScrollCoordinate(
        point: CGFloat,
        currentOrigin: CGFloat,
        contentLength: CGFloat,
        viewportLength: CGFloat,
        maxValue: CGFloat
    ) -> CGFloat {
        guard contentLength > viewportLength else { return currentOrigin }
        return min(max(0, point - viewportLength / 2), maxValue)
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
