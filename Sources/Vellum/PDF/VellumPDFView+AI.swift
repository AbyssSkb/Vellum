@preconcurrency import AppKit
import PDFKit
import SwiftUI

extension VellumPDFView {
    func updateHoveredAIExplanation(for event: NSEvent) {
        if aiInteraction.activeExplanationModel != nil, aiInteraction.hoveredAnnotation == nil {
            return
        }

        if isMouseSelectingText || currentSelection != nil || NSEvent.pressedMouseButtons != 0 {
            hideAIExplanationPopover()
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        guard let annotation = aiExplanationAnnotation(at: point),
              let explanation = AIExplanationAnnotation.decode(annotation.contents) else {
            if let suppressedHoverAnnotation = aiInteraction.suppressedHoverAnnotation,
               let suppressedHoverText = aiInteraction.suppressedHoverText,
               isPoint(point, insideExplanationGroupFor: suppressedHoverAnnotation, explanation: suppressedHoverText) {
                hideAIExplanationPopover()
                return
            }

            if let hoveredAnnotation = aiInteraction.hoveredAnnotation,
               let hoveredText = aiInteraction.hoveredText,
               isPoint(point, insideExplanationGroupFor: hoveredAnnotation, explanation: hoveredText) {
                cancelPendingHoverPopoverHide()
                return
            }

            clearSuppressedHoverExplanation()
            scheduleHoverPopoverHide()
            return
        }
        let hoverKey = hoverExplanationKey(for: annotation, explanation: explanation)

        if aiInteraction.suppressedHoverKey == hoverKey {
            hideAIExplanationPopover()
            return
        }
        clearSuppressedHoverExplanation()

        cancelPendingHoverPopoverHide()

        if aiInteraction.hoveredKey == hoverKey,
           aiInteraction.hoveredText == explanation,
           aiInteraction.explanationPopover?.isShown == true {
            aiInteraction.hoveredAnnotation = annotation
            return
        }

        showAIExplanationPopover(explanation, at: point, annotation: annotation, hoverKey: hoverKey)
    }

    func aiExplanationAnnotation(at pointInView: NSPoint) -> PDFAnnotation? {
        guard let page = page(for: pointInView, nearest: false) else { return nil }

        let pointOnPage = convert(pointInView, to: page)
        return page.annotations.reversed().first { annotation in
            annotation.type == "Highlight"
                && AIExplanationAnnotation.decode(annotation.contents) != nil
                && HighlightGeometry.regions(for: annotation).contains { region in
                    region.insetBy(dx: -2, dy: -2).contains(pointOnPage)
                }
        }
    }

    func showAIExplanationPopover(
        _ explanation: String,
        at point: NSPoint,
        annotation: PDFAnnotation,
        hoverKey: String
    ) {
        let model = AIExplanationPopoverModel(
            title: "Saved explanation",
            text: explanation,
            initialHeight: AIExplanationPopoverMetrics.estimatedHoverHeight(for: explanation)
        )
        showPopover(
            model: model,
            at: explanationPopoverAnchorRect(for: annotation, explanation: explanation, fallbackPoint: point),
            kind: .hover
        )
        clearSuppressedHoverExplanation()
        aiInteraction.hoveredAnnotation = annotation
        aiInteraction.hoveredText = explanation
        aiInteraction.hoveredKey = hoverKey
    }

    func showAIMessage(_ message: String, at rect: NSRect? = nil) {
        let model = AIExplanationPopoverModel(
            title: "Vellum",
            text: message,
            initialHeight: AIExplanationPopoverMetrics.compactInitialHeight
        )
        showPopover(model: model, at: rect ?? selectionPopoverRect(for: currentSelection), kind: .message)
        clearSuppressedHoverExplanation()
        aiInteraction.hoveredAnnotation = nil
        aiInteraction.hoveredText = message
        aiInteraction.hoveredKey = nil
    }

    func showStreamingAIExplanationPopover(
        title: String,
        at rect: NSRect?
    ) -> AIExplanationPopoverModel? {
        let model = AIExplanationPopoverModel(
            title: title,
            isStreaming: true,
            initialHeight: AIExplanationPopoverMetrics.streamingMinimumHeight
        )
        showPopover(model: model, at: rect ?? selectionPopoverRect(for: currentSelection), kind: .streaming)
        clearSuppressedHoverExplanation()
        aiInteraction.hoveredAnnotation = nil
        aiInteraction.hoveredText = nil
        aiInteraction.hoveredKey = nil
        return model
    }

    func showPopover(
        model: AIExplanationPopoverModel,
        at rect: NSRect?,
        kind: AIExplanationPopoverKind
    ) {
        guard window != nil else { return }
        cancelPendingHoverPopoverHide()
        hideAIExplanationPopover()

        let popover = NSPopover()
        popover.behavior = kind.behavior
        popover.animates = kind.animates
        popover.contentSize = model.preferredSize
        popover.contentViewController = NSHostingController(
            rootView: AIExplanationPopoverView(
                model: model,
                kind: kind,
                onDismiss: { [weak self] in
                    switch kind {
                    case .hover:
                        self?.dismissHoverAIExplanation(suppressCurrent: true)
                    case .message, .streaming:
                        self?.dismissActiveAIInteraction(clearSelection: true)
                    }
                },
                onHighlight: { [weak self] in
                    self?.highlightActiveAISelection()
                },
                onCycleColor: { [weak self] in
                    self?.appState?.cycleHighlightColor(preserveFocus: true)
                },
                onContentHeightChange: { [weak self, model, kind] contentHeight in
                    guard kind.allowsDynamicHeight else { return }

                    switch kind {
                    case .streaming:
                        self?.scheduleStreamingPopoverHeightUpdate(model: model, contentHeight: contentHeight)
                    case .message:
                        self?.applyPopoverHeight(model: model, contentHeight: contentHeight, scrollToBottom: false)
                    case .hover:
                        self?.applyPopoverHeight(
                            model: model,
                            contentHeight: contentHeight,
                            minimumHeight: AIExplanationPopoverMetrics.hoverMinimumHeight,
                            scrollToBottom: false
                        )
                    }
                },
                onWebViewReady: { [weak self, kind] webView in
                    self?.aiInteraction.activeWebView = webView
                    guard kind.shouldFocusWebView else { return }

                    DispatchQueue.main.async { [weak webView] in
                        guard let webView else { return }
                        webView.window?.makeFirstResponder(webView)
                    }
                }
            )
        )

        let anchor = rect ?? NSRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
        popover.show(relativeTo: anchor, of: self, preferredEdge: .maxY)
        aiInteraction.explanationPopover = popover
        aiInteraction.activeExplanationModel = model
    }

    func scheduleStreamingPopoverHeightUpdate(model: AIExplanationPopoverModel, contentHeight: CGFloat) {
        aiInteraction.pendingPopoverContentHeight = contentHeight

        guard aiInteraction.popoverHeightUpdateWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self, model] in
            guard let self else { return }

            let latestHeight = self.aiInteraction.pendingPopoverContentHeight ?? contentHeight
            self.aiInteraction.pendingPopoverContentHeight = nil
            self.aiInteraction.popoverHeightUpdateWorkItem = nil
            self.applyPopoverHeight(
                model: model,
                contentHeight: latestHeight,
                minimumHeight: AIExplanationPopoverMetrics.streamingMinimumHeight,
                scrollToBottom: true
            )
        }
        aiInteraction.popoverHeightUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.045, execute: workItem)
    }

    func applyPopoverHeight(
        model: AIExplanationPopoverModel,
        contentHeight: CGFloat,
        minimumHeight: CGFloat = AIExplanationPopoverMetrics.minimumHeight,
        scrollToBottom: Bool
    ) {
        guard aiInteraction.activeExplanationModel === model else { return }

        if model.updateContentHeight(contentHeight, minimumHeight: minimumHeight) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                aiInteraction.explanationPopover?.contentSize = model.preferredSize
            }
        }

        if scrollToBottom, let webView = aiInteraction.activeWebView {
            let shouldStickToBottom = ceil(contentHeight) > model.maximumHeight + 1
            let alignScroll = { [weak webView] in
                if shouldStickToBottom {
                    webView?.scrollToBottom()
                } else {
                    webView?.scrollToTop()
                }
            }

            alignScroll()
            DispatchQueue.main.async {
                alignScroll()
            }
        }
    }

    func hideAIExplanationPopover() {
        cancelPendingHoverPopoverHide()
        stopAIContinuousScroll()
        aiInteraction.clearPopoverState()
    }

    func dismissHoverAIExplanation(suppressCurrent: Bool) {
        if suppressCurrent, let hoveredKey = aiInteraction.hoveredKey {
            aiInteraction.suppressedHoverKey = hoveredKey
            aiInteraction.suppressedHoverAnnotation = aiInteraction.hoveredAnnotation
            aiInteraction.suppressedHoverText = aiInteraction.hoveredText
        }
        hideAIExplanationPopover()
        focus()
    }

    func clearSuppressedHoverExplanation() {
        aiInteraction.clearSuppressedHover()
    }

    func explanationPopoverAnchorRect(
        for annotation: PDFAnnotation,
        explanation: String,
        fallbackPoint: NSPoint
    ) -> NSRect {
        guard let page = annotation.page else {
            return NSRect(x: fallbackPoint.x, y: fallbackPoint.y, width: 1, height: 1)
        }

        let annotations = explanationAnnotations(matching: explanation, on: page)
        let sourceAnnotations = annotations.isEmpty ? [annotation] : annotations
        let points = sourceAnnotations.flatMap { annotation in
            HighlightGeometry.regions(for: annotation).flatMap { region in
                [
                    NSPoint(x: region.minX, y: region.minY),
                    NSPoint(x: region.maxX, y: region.minY),
                    NSPoint(x: region.minX, y: region.maxY),
                    NSPoint(x: region.maxX, y: region.maxY)
                ]
            }
        }

        guard let pageRect = HighlightGeometry.rect(containing: points) ?? HighlightGeometry.rect(containing: [
            NSPoint(x: annotation.bounds.minX, y: annotation.bounds.minY),
            NSPoint(x: annotation.bounds.maxX, y: annotation.bounds.maxY)
        ]),
              let viewRect = viewRect(for: pageRect, on: page) else {
            return NSRect(x: fallbackPoint.x, y: fallbackPoint.y, width: 1, height: 1)
        }

        return viewRect.insetBy(dx: -3, dy: -3)
    }

    func explanationAnnotations(matching explanation: String, on page: PDFPage) -> [PDFAnnotation] {
        page.annotations.filter { annotation in
            annotation.type == "Highlight"
                && AIExplanationAnnotation.decode(annotation.contents) == explanation
        }
    }

    func hoverExplanationKey(for annotation: PDFAnnotation, explanation: String) -> String {
        let pageIndex: Int
        if let page = annotation.page, let document {
            let index = document.index(for: page)
            pageIndex = index == NSNotFound ? -1 : index
        } else {
            pageIndex = -1
        }

        return "\(pageIndex):\(explanation)"
    }

    func scheduleHoverPopoverHide() {
        guard aiInteraction.hoveredAnnotation != nil else { return }

        aiInteraction.hoverPopoverHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.hideHoverPopoverIfNeeded()
        }
        aiInteraction.hoverPopoverHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: workItem)
    }

    func hideHoverPopoverIfNeeded() {
        guard let hoveredKey = aiInteraction.hoveredKey else { return }

        if mouseIsHoveringExplanationGroup(hoveredKey)
            || mouseIsInsideExplanationPopover() {
            scheduleHoverPopoverHide()
            return
        }

        hideAIExplanationPopover()
    }

    func cancelPendingHoverPopoverHide() {
        aiInteraction.hoverPopoverHideWorkItem?.cancel()
        aiInteraction.hoverPopoverHideWorkItem = nil
    }

    func mouseIsInsideExplanationPopover() -> Bool {
        guard let popoverWindow = aiInteraction.explanationPopover?.contentViewController?.view.window else {
            return false
        }

        return popoverWindow.frame.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation)
    }

    func mouseIsHoveringExplanationGroup(_ hoverKey: String) -> Bool {
        guard let point = currentMousePointInView(),
              bounds.insetBy(dx: -4, dy: -4).contains(point) else { return false }

        if let annotation = aiExplanationAnnotation(at: point),
           let explanation = AIExplanationAnnotation.decode(annotation.contents) {
            return hoverExplanationKey(for: annotation, explanation: explanation) == hoverKey
        }

        guard let hoveredAnnotation = aiInteraction.hoveredAnnotation,
              let hoveredText = aiInteraction.hoveredText,
              aiInteraction.hoveredKey == hoverKey else { return false }

        return isPoint(point, insideExplanationGroupFor: hoveredAnnotation, explanation: hoveredText)
    }

    func isPoint(
        _ pointInView: NSPoint,
        insideExplanationGroupFor referenceAnnotation: PDFAnnotation,
        explanation: String
    ) -> Bool {
        guard let page = referenceAnnotation.page else { return false }

        let annotations = explanationAnnotations(matching: explanation, on: page)
        let sourceAnnotations = annotations.isEmpty ? [referenceAnnotation] : annotations
        let points = sourceAnnotations.flatMap { annotation in
            HighlightGeometry.regions(for: annotation).flatMap { region in
                [
                    NSPoint(x: region.minX, y: region.minY),
                    NSPoint(x: region.maxX, y: region.minY),
                    NSPoint(x: region.minX, y: region.maxY),
                    NSPoint(x: region.maxX, y: region.maxY)
                ]
            }
        }

        guard let groupBounds = HighlightGeometry.rect(containing: points) else { return false }
        let pointOnPage = convert(pointInView, to: page)
        return groupBounds.insetBy(dx: -5, dy: -8).contains(pointOnPage)
    }

    func currentMousePointInView() -> NSPoint? {
        guard let window else { return nil }

        let pointInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return convert(pointInWindow, from: nil)
    }

    func handleAIKeyEvent(_ event: NSEvent) -> Bool {
        guard isAIInteractionActive else { return false }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        guard let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return false }

        switch AIKeyEventRouter.action(
            key: key,
            eventType: event.type,
            hasHoveredExplanation: aiInteraction.hoveredKey != nil,
            continuousScrollKey: aiInteraction.continuousScrollKey
        ) {
        case .none:
            return false
        case .dismissHover:
            dismissHoverAIExplanation(suppressCurrent: true)
            return true
        case .startContinuousScroll(let directionKey):
            startAIContinuousScroll(directionKey)
            return true
        case .stopContinuousScroll:
            stopAIContinuousScroll()
            return true
        case .forwardToWebView(let key):
            if aiInteraction.activeWebView?.handleKey(key) == true {
                return true
            }
            return true
        case .consume:
            return true
        }
    }

    func startAIContinuousScroll(_ key: String) {
        guard aiInteraction.continuousScrollKey != key else { return }

        aiInteraction.continuousScrollKey = key
        aiInteraction.activeWebView?.startContinuousScroll(direction: key == "j" ? 1 : -1)
    }

    func stopAIContinuousScroll() {
        aiInteraction.continuousScrollKey = nil
        aiInteraction.activeWebView?.stopContinuousScroll()
    }

    func dismissActiveAIInteraction(clearSelection shouldClearSelection: Bool) {
        aiInteraction.clearActiveRequest()
        if shouldClearSelection {
            clearSelection()
            textSelectionNavigationState = nil
        }
        hideAIExplanationPopover()
        focus()
    }

    func highlightActiveAISelection() {
        guard let selection = aiInteraction.activeSelection ?? currentSelection else {
            dismissActiveAIInteraction(clearSelection: true)
            return
        }

        aiInteraction.explanationTask?.cancel()
        aiInteraction.explanationTask = nil

        let color = appState?.selectedHighlightColor.annotationColor ?? HighlightColor.yellow.annotationColor
        let annotations = addHighlightAnnotations(for: selection, color: color)
        let explanation = aiInteraction.activeExplanationModel?.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        if let explanation {
            for annotation in annotations {
                annotation.contents = AIExplanationAnnotation.encode(explanation)
                annotation.userName = "Vellum AI"
                annotation.modificationDate = Date()
            }
        }

        needsDisplay = true
        persistAnnotationsIfPossible()
        dismissActiveAIInteraction(clearSelection: true)
    }

    func selectionPopoverRect(for selection: PDFSelection?) -> NSRect? {
        guard let selection else { return nil }

        let lineSelections = selection.selectionsByLine()
        let selections = lineSelections.isEmpty ? [selection] : lineSelections

        for lineSelection in selections {
            for page in lineSelection.pages {
                guard let bounds = HighlightGeometry.tightBounds(for: lineSelection, on: page),
                      let viewRect = viewRect(for: bounds, on: page) else { continue }
                return viewRect
            }
        }

        return nil
    }

    func viewRect(for pageRect: NSRect, on page: PDFPage) -> NSRect? {
        HighlightGeometry.rect(containing: [
            convert(NSPoint(x: pageRect.minX, y: pageRect.minY), from: page),
            convert(NSPoint(x: pageRect.maxX, y: pageRect.minY), from: page),
            convert(NSPoint(x: pageRect.minX, y: pageRect.maxY), from: page),
            convert(NSPoint(x: pageRect.maxX, y: pageRect.maxY), from: page)
        ])
    }
}
