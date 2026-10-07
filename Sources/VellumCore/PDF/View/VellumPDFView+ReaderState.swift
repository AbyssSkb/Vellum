@preconcurrency import AppKit
import PDFKit

extension VellumPDFView {
    func readingDestination() -> PDFDestination? {
        guard let document, let snapshot = snapshot(), let page = document.page(at: snapshot.pageIndex) else { return nil }
        return PDFDestination(page: page, at: snapshot.pointOnPage)
    }

    func readingPositionChanged(from previous: PDFDestination?) -> Bool {
        guard let previous, let current = readingDestination() else { return false }
        return current.page !== previous.page || abs(current.point.x - previous.point.x) > 0.5
            || abs(current.point.y - previous.point.y) > 0.5
    }

    func pinReadingSection(at destination: PDFDestination) {
        pendingReadingNavigation = false
        appState?.updateOutlineReadingPosition(destination, from: self, userNavigated: true, pinSection: true)
        scheduleReadingPositionReport()
    }

    func scheduleReadingPositionReport(userNavigated: Bool = false) {
        guard let document else { return }
        pendingReadingNavigation = pendingReadingNavigation || userNavigated
        readingPositionReportWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak document] in
            MainActor.assumeIsolated {
                guard let self, let document, self.document === document,
                      !self.isPageOverviewActive, self.finishingPageOverviewGeneration == nil,
                      self.pendingRestoreAction == nil,
                      let destination = self.readingDestination() else { return }
                let userNavigated = self.pendingReadingNavigation
                self.pendingReadingNavigation = false
                self.appState?.updateOutlineReadingPosition(destination, from: self, userNavigated: userNavigated)
            }
        }
        readingPositionReportWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
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
        pendingReadingNavigation = false
        restoreGeneration += 1
        let generation = restoreGeneration
        pendingRestoreAction = nil
        stopScrollAnimation()
        stopZoomState()

        if snapshot == .initial {
            pendingRestoreAction = .initial(generation: generation)
            restoreInitialDocumentPosition(generation: generation)
            return
        }

        guard let snapshot, let document, let page = document.page(at: snapshot.pageIndex) else {
            _ = applyWidthFitScaleNow()
            scheduleReadingPositionReport()
            return
        }

        pendingRestoreAction = .snapshot(snapshot: snapshot, page: page, generation: generation)
        restoreSnapshotPosition(snapshot, page: page, generation: generation)
    }

    func restoreSnapshotPosition(
        _ snapshot: ReaderSnapshot,
        page: PDFPage,
        generation: Int,
        attemptsRemaining: Int = 30,
        stablePasses: Int = 0,
        lastViewportSize: NSSize? = nil
    ) {
        guard generation == restoreGeneration else { return }

        let viewportSize = applySnapshotPosition(snapshot, page: page)

        let nextStablePasses: Int
        if let viewportSize,
           let lastViewportSize,
           isSameViewportSize(viewportSize, lastViewportSize) {
            nextStablePasses = stablePasses + 1
        } else {
            nextStablePasses = 0
        }

        guard attemptsRemaining > 0, nextStablePasses < 2 else {
            clearPendingRestoreAction(generation: generation)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.restoreSnapshotPosition(
                snapshot,
                page: page,
                generation: generation,
                attemptsRemaining: attemptsRemaining - 1,
                stablePasses: nextStablePasses,
                lastViewportSize: viewportSize
            )
        }
    }

    func restoreInitialDocumentPosition(
        generation: Int,
        attemptsRemaining: Int = 30,
        stablePasses: Int = 0,
        lastViewportSize: NSSize? = nil
    ) {
        guard generation == restoreGeneration else { return }

        let appliedPosition = applyInitialDocumentPositionOnce()
        let viewportSize = appliedPosition.viewportSize
        let didApplyZoom = appliedPosition.didApplyZoom

        let nextStablePasses: Int
        if didApplyZoom,
           let viewportSize,
           let lastViewportSize,
           isSameViewportSize(viewportSize, lastViewportSize) {
            nextStablePasses = stablePasses + 1
        } else {
            nextStablePasses = 0
        }

        guard attemptsRemaining > 0, (!didApplyZoom || nextStablePasses < 2) else {
            clearPendingRestoreAction(generation: generation)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.restoreInitialDocumentPosition(
                generation: generation,
                attemptsRemaining: attemptsRemaining - 1,
                stablePasses: nextStablePasses,
                lastViewportSize: viewportSize
            )
        }
    }

    func completePendingRestoreBeforeUserInteraction() {
        guard let pendingRestoreAction,
              pendingRestoreAction.generation == restoreGeneration else { return }

        switch pendingRestoreAction {
        case .initial:
            _ = applyInitialDocumentPositionOnce()
        case .snapshot(let snapshot, let page, _):
            _ = applySnapshotPosition(snapshot, page: page)
        }

        cancelPendingRestore()
    }

    func clearPendingRestoreAction(generation: Int) {
        guard pendingRestoreAction?.generation == generation else { return }
        pendingRestoreAction = nil
        scheduleReadingPositionReport()
    }

    @discardableResult
    func applySnapshotPosition(_ snapshot: ReaderSnapshot, page: PDFPage) -> NSSize? {
        let viewportSize = fitViewportSize()
        autoScales = false
        if snapshot.autoScales {
            _ = applyWidthFitScaleNow(for: page)
        } else {
            scaleFactor = snapshot.scaleFactor
            layoutDocumentView()
            needsDisplay = true
        }

        go(to: PDFDestination(page: page, at: snapshot.pointOnPage))
        restoreScrollOrigin(snapshot.scrollOrigin)
        return viewportSize
    }

    func applyInitialDocumentPositionOnce() -> (viewportSize: NSSize?, didApplyZoom: Bool) {
        let viewportSize = fitViewportSize()
        let didApplyZoom = applyInitialZoomBehavior(for: document?.page(at: 0))
        if didApplyZoom {
            goToFirstPage(nil)
            scrollToDocumentEdge(.top)
        }
        return (viewportSize, didApplyZoom)
    }

    @discardableResult
    func applyInitialZoomBehavior(for page: PDFPage?) -> Bool {
        switch AppPreferences.openFileZoomBehavior() {
        case .fitWidth:
            return applyWidthFitScaleNow(for: page)
        case .fitPage:
            guard let page,
                  let fitScale = pageFitScale(for: page) else { return false }
            autoScales = false
            scaleFactor = fitScale
            layoutDocumentView()
            needsDisplay = true
            return true
        }
    }

    func recordJumpSource(_ source: ReaderSnapshot? = nil) {
        guard let current = source ?? snapshot() else { return }

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
        let restoredBounds = clipView.constrainBoundsRect(NSRect(origin: origin, size: clipView.bounds.size))
        clipView.scroll(to: restoredBounds.origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    func persistAnnotationsIfPossible() {
        guard let document, let persistence = PDFAnnotationPersistence.state(for: document) else { return }
        persistence.save(document) { [weak appState] in
            appState?.resolveAnnotationFailure(for: document)
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
}
