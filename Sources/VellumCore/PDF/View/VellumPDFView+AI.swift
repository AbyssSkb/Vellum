@preconcurrency import AppKit
import PDFKit
import SwiftUI

extension VellumPDFView {
    func updateHoveredAIExplanation(for event: NSEvent) {
        if (aiInteraction.activeExplanationModel != nil || aiInteraction.activeConversationModel != nil),
           aiInteraction.hoveredAnnotation == nil {
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
            initialHeight: AIExplanationPopoverMetrics.estimatedHoverHeight(for: explanation),
            pronunciationSpeechText: pronunciationSpeechText(for: annotation, explanation: explanation)
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
        showAIToast(message)
        clearSuppressedHoverExplanation()
        aiInteraction.hoveredAnnotation = nil
        aiInteraction.hoveredText = message
        aiInteraction.hoveredKey = nil
    }

    func showAINotification(_ message: String) {
        showAIToast(message)
    }

    func showAIToast(_ message: String) {
        guard window != nil else { return }

        dismissAIToast()

        let toast = AIToastView(message: message)
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.alphaValue = 0
        toast.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(dismissAIToast)))
        addSubview(toast)

        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: centerXAnchor),
            toast.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            toast.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 18),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18)
        ])

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            toast.animator().alphaValue = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.dismissAIToast()
        }
        aiInteraction.toastView = toast
        aiInteraction.toastHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: workItem)
    }

    @objc func dismissAIToast() {
        aiInteraction.toastHideWorkItem?.cancel()
        aiInteraction.toastHideWorkItem = nil

        guard let toast = aiInteraction.toastView else { return }
        aiInteraction.toastView = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            toast.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                toast.removeFromSuperview()
            }
        }
    }

    func showStreamingAIExplanationPopover(
        title: String,
        pronunciationSpeechText: String?,
        at rect: NSRect?
    ) -> AIExplanationPopoverModel? {
        let model = AIExplanationPopoverModel(
            title: title,
            isStreaming: true,
            initialHeight: AIExplanationPopoverMetrics.streamingMinimumHeight,
            pronunciationSpeechText: pronunciationSpeechText
        )
        showPopover(model: model, at: rect, kind: .streaming)
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

        guard kind == .hover else {
            showAIExplanationWindow(model: model, kind: kind)
            return
        }

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
        let horizontalOrigin = currentHorizontalOrigin()
        if horizontalOrigin != nil {
            window?.disableScreenUpdatesUntilFlush()
        }
        popover.show(relativeTo: anchor, of: self, preferredEdge: .maxY)
        restoreHorizontalOrigin(horizontalOrigin)
        DispatchQueue.main.async { [weak self] in
            self?.restoreHorizontalOrigin(horizontalOrigin)
        }
        aiInteraction.explanationPopover = popover
        aiInteraction.activeExplanationModel = model
    }

    private func showAIExplanationWindow(
        model: AIExplanationPopoverModel,
        kind: AIExplanationPopoverKind
    ) {
        guard let parentWindow = window else { return }

        let hostingController = NSHostingController(
            rootView: AIExplanationPopoverView(
                model: model,
                kind: kind,
                onDismiss: { [weak self] in
                    self?.dismissActiveAIInteraction(clearSelection: true)
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
                        break
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

        let panel = AIFloatingPanel(contentRect: NSRect(origin: .zero, size: model.preferredSize))
        panel.contentViewController = hostingController
        panel.setContentSize(model.preferredSize)
        positionAIFloatingWindow(panel, size: model.preferredSize)
        parentWindow.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)

        aiInteraction.explanationWindow = panel
        aiInteraction.activeExplanationModel = model
        installAIFloatingWindowDismissMonitor()
        installAIFloatingWindowActivationObserver()
    }

    func showAIConversationPopover(
        model: AIConversationPopoverModel,
        at rect: NSRect?
    ) {
        guard window != nil else { return }
        cancelPendingHoverPopoverHide()
        hideAIExplanationPopover()

        showAIConversationWindow(model: model)
    }

    private func showAIConversationWindow(model: AIConversationPopoverModel) {
        guard let parentWindow = window else { return }

        let panel = AIFloatingPanel(contentRect: NSRect(origin: .zero, size: model.preferredSize))
        panel.contentViewController = NSHostingController(
            rootView: AIConversationPopoverView(
                model: model,
                onDismiss: { [weak self] in
                    self?.dismissActiveAIInteraction(clearSelection: true)
                },
                onSend: { [weak self, weak model] prompt in
                    self?.sendAIConversationMessage(prompt, model: model)
                },
                onPreferredSizeChange: { [weak self, weak panel] size in
                    guard let self, let panel else { return }
                    self.resizeAIFloatingWindow(panel, size: size)
                }
            )
        )
        panel.setContentSize(model.preferredSize)
        positionAIFloatingWindow(panel, size: model.preferredSize)
        parentWindow.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)

        aiInteraction.conversationWindow = panel
        aiInteraction.activeConversationModel = model
        installAIFloatingWindowDismissMonitor()
        installAIFloatingWindowActivationObserver()
    }

    private func installAIFloatingWindowDismissMonitor() {
        if let floatingWindowDismissMonitor = aiInteraction.floatingWindowDismissMonitor {
            NSEvent.removeMonitor(floatingWindowDismissMonitor)
        }

        aiInteraction.floatingWindowDismissMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            guard self.aiInteraction.explanationWindow?.isVisible == true
                || self.aiInteraction.conversationWindow?.isVisible == true else {
                return event
            }

            if self.eventIsInsideActiveAIFloatingWindow(event) {
                return event
            }

            self.dismissActiveAIInteraction(clearSelection: true)
            return event
        }
    }

    private func installAIFloatingWindowActivationObserver() {
        guard aiInteraction.floatingWindowActivationObserver == nil else { return }

        aiInteraction.floatingWindowActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restoreAIFloatingWindowPresentation()
            }
        }
    }

    private func eventIsInsideActiveAIFloatingWindow(_ event: NSEvent) -> Bool {
        if let explanationWindow = aiInteraction.explanationWindow,
           event.window === explanationWindow {
            return true
        }

        if let conversationWindow = aiInteraction.conversationWindow,
           event.window === conversationWindow {
            return true
        }

        return false
    }

    private func resizeAIFloatingWindow(_ window: NSWindow, size: NSSize) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            positionAIFloatingWindow(window, size: size)
        }
    }

    func restoreAIFloatingWindowPresentation() {
        guard isAIInteractionActive,
              let parentWindow = window,
              parentWindow.isVisible else {
            return
        }

        if let explanationWindow = aiInteraction.explanationWindow,
           let activeExplanationModel = aiInteraction.activeExplanationModel {
            restoreAIFloatingWindow(
                explanationWindow,
                parentWindow: parentWindow,
                size: activeExplanationModel.preferredSize,
                makeKey: aiInteraction.activeConversationModel == nil
            )
        }

        if let conversationWindow = aiInteraction.conversationWindow,
           let activeConversationModel = aiInteraction.activeConversationModel {
            restoreAIFloatingWindow(
                conversationWindow,
                parentWindow: parentWindow,
                size: activeConversationModel.preferredSize,
                makeKey: true
            )
            refocusAIConversationInput(in: conversationWindow)
        }
    }

    private func restoreAIFloatingWindow(
        _ floatingWindow: NSWindow,
        parentWindow: NSWindow,
        size: NSSize,
        makeKey: Bool
    ) {
        if floatingWindow.parent !== parentWindow {
            floatingWindow.parent?.removeChildWindow(floatingWindow)
            parentWindow.addChildWindow(floatingWindow, ordered: .above)
        }

        positionAIFloatingWindow(floatingWindow, size: size)
        if makeKey {
            floatingWindow.makeKeyAndOrderFront(nil)
        } else {
            floatingWindow.orderFront(nil)
        }
    }

    private func refocusAIConversationInput(in window: NSWindow) {
        guard let textView = firstTextView(in: window.contentView) else { return }
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
        textView.needsDisplay = true
    }

    private func firstTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView {
            return textView
        }

        for subview in view.subviews {
            if let textView = firstTextView(in: subview) {
                return textView
            }
        }

        return nil
    }

    private func positionAIFloatingWindow(_ floatingWindow: NSWindow, size: NSSize) {
        guard let parentWindow = window else { return }

        let visible = visibleRect
        let topInset: CGFloat = 76
        let minimumInset: CGFloat = 18
        let originInView = NSPoint(
            x: visible.midX - size.width / 2,
            y: max(visible.minY + minimumInset, visible.maxY - topInset - size.height)
        )
        let viewRect = NSRect(origin: originInView, size: size)
        let windowRect = convert(viewRect, to: nil)
        let screenRect = parentWindow.convertToScreen(windowRect)
        floatingWindow.setFrame(screenRect, display: true)
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
                if let explanationWindow = aiInteraction.explanationWindow {
                    positionAIFloatingWindow(explanationWindow, size: model.preferredSize)
                }
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
        aiInteraction.activeWebView?.stopPronunciation()
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
            return AIExplanationGeometry.fallbackAnchorRect(at: fallbackPoint)
        }

        let annotations = explanationAnnotations(matching: explanation, on: page)
        let sourceAnnotations = annotations.isEmpty ? [annotation] : annotations
        let regions = sourceAnnotations.flatMap(HighlightGeometry.regions)

        guard let pageRect = AIExplanationGeometry.groupBounds(for: regions, fallbackBounds: annotation.bounds),
              let viewRect = viewRect(for: pageRect, on: page) else {
            return AIExplanationGeometry.fallbackAnchorRect(at: fallbackPoint)
        }

        return AIExplanationGeometry.popoverAnchorRect(from: viewRect)
    }

    func explanationAnnotations(matching explanation: String, on page: PDFPage) -> [PDFAnnotation] {
        page.annotations.filter { annotation in
            annotation.type == "Highlight"
                && AIExplanationAnnotation.decode(annotation.contents) == explanation
        }
    }

    func pronunciationSpeechText(for annotation: PDFAnnotation, explanation: String) -> String? {
        guard let page = annotation.page else { return nil }

        let annotations = explanationAnnotations(matching: explanation, on: page)
        let sourceAnnotations = annotations.isEmpty ? [annotation] : annotations
        let text = sourceAnnotations
            .sorted { lhs, rhs in
                if abs(lhs.bounds.midY - rhs.bounds.midY) > 2 {
                    return lhs.bounds.midY > rhs.bounds.midY
                }
                return lhs.bounds.minX < rhs.bounds.minX
            }
            .compactMap { sourceAnnotation in
                sourceAnnotation.page?
                    .selection(for: sourceAnnotation.bounds.insetBy(dx: -1, dy: -1))?
                    .string?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
            }
            .joined(separator: " ")

        return AIExplanationPronunciationSpeech.normalizedSelectionText(text)
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
        if let explanationWindow = aiInteraction.explanationWindow,
           explanationWindow.frame.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation) {
            return true
        }

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
        let regions = sourceAnnotations.flatMap(HighlightGeometry.regions)

        guard let groupBounds = AIExplanationGeometry.groupBounds(for: regions) else { return false }
        let pointOnPage = convert(pointInView, to: page)
        return AIExplanationGeometry.hoverContains(pointOnPage, in: groupBounds)
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

        if aiInteraction.activeConversationModel != nil {
            if key == "\u{1b}", event.type == .keyDown {
                dismissActiveAIInteraction(clearSelection: true)
                return true
            }
            return false
        }

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

    func aiExplanationHistoryItems() -> [AIExplanationHistoryItem] {
        guard let document else { return [] }

        var items: [AIExplanationHistoryItem] = []
        var seen = Set<String>()

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            for annotation in page.annotations where annotation.type == "Highlight" {
                guard let explanation = AIExplanationAnnotation.decode(annotation.contents) else { continue }

                let groupID = HighlightAnnotationMetadata.groupID(for: annotation)
                let key = groupID ?? "\(pageIndex):\(annotation.bounds.integral.debugDescription):\(explanation)"
                guard seen.insert(key).inserted else { continue }

                let selectedText = page.selection(for: annotation.bounds)?.string?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
                    ?? explanation.aiPopoverTitle

                items.append(
                    AIExplanationHistoryItem(
                        id: UUID(),
                        selectedText: selectedText,
                        explanation: explanation,
                        fileName: document.documentURL?.lastPathComponent ?? "Untitled",
                        documentKey: document.documentURL?.standardizedFileURL.path,
                        pageNumbers: [pageIndex + 1],
                        updatedAt: annotation.modificationDate ?? Date.distantPast
                    )
                )
            }
        }

        return items.sorted { $0.updatedAt > $1.updatedAt }
    }

    func restoreAIExplanation(_ item: AIExplanationHistoryItem) {
        aiInteraction.explanationTask?.cancel()
        aiInteraction.activeSelection = nil
        aiInteraction.existingAnnotations = []

        let model = AIExplanationPopoverModel(
            title: item.selectedText.aiPopoverTitle,
            text: item.explanation,
            initialHeight: AIExplanationPopoverMetrics.estimatedHeight(for: item.explanation),
            pronunciationSpeechText: item.selectedText
        )
        showPopover(model: model, at: centeredPopoverRect(), kind: .message)
    }

    func restoreAIConversation(_ item: AIConversationHistoryItem) {
        aiInteraction.conversationTask?.cancel()

        let model = AIConversationPopoverModel(context: item.context, historyID: item.id)
        model.messages = item.messages
        model.refreshPreferredHeight()
        showAIConversationPopover(model: model, at: centeredPopoverRect())
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

    func centeredPopoverRect() -> NSRect {
        NSRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
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

private final class AIFloatingPanel: NSWindow {
    private static let cornerRadius: CGFloat = 8

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.fullScreenAuxiliary]
    }

    override var contentView: NSView? {
        didSet {
            contentView?.wantsLayer = true
            contentView?.layer?.cornerRadius = Self.cornerRadius
            contentView?.layer?.cornerCurve = .continuous
            contentView?.layer?.masksToBounds = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class AIToastView: NSView {
    init(message: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = TokyoNight.panelElevated.withAlphaComponent(0.96).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = TokyoNight.border.withAlphaComponent(0.85).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.24
        layer?.shadowRadius = 14
        layer?.shadowOffset = NSSize(width: 0, height: -5)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)
        icon.contentTintColor = TokyoNight.cyan
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = TokyoNight.foreground
        label.backgroundColor = .clear
        label.isBezeled = false
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
