@preconcurrency import AppKit
import PDFKit

extension VellumPDFView {
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
}
