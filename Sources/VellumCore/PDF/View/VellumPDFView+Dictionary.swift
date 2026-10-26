@preconcurrency import AppKit
import PDFKit

extension VellumPDFView {
    var isDictionaryInteractionActive: Bool {
        dictionaryOverlay?.superview != nil
    }

    func vimLookupDictionary() {
        guard appState == nil || appState?.activeReaderController === self else { return }
        let text = AISelectedTextNormalizer.normalized(currentSelection?.string ?? "")
        guard !text.isEmpty else {
            showNotification(AppUILanguage.saved().text(.dictionaryNoSelection))
            return
        }
        guard let window else { return }

        cancelWordJump()
        cancelLinkPreview()
        stopScrollAnimation()
        stopZoomState()
        hideAIExplanationPopover()

        if let dictionaryPopover {
            dictionaryPopover.lookup(text)
            return
        }

        let popover = DictionaryPopoverView()
        popover.onDismiss = { [weak self] in self?.dismissDictionaryPopover() }
        popover.onPreferredHeightChange = { [weak self, weak popover] height in
            guard let self, let popover, self.dictionaryPopover === popover else { return }
            self.dictionaryPreferredHeight = height
            self.updateDictionaryOverlayFrame()
        }
        let overlay = AIFloatingOverlayContainerView(contentView: popover)
        dictionaryPopover = popover
        dictionaryOverlay = overlay
        dictionaryPreferredHeight = popover.preferredHeight
        updateDictionaryOverlayFrame()
        addSubview(overlay)
        selectionEndpointOverlay?.isHidden = true
        window.makeFirstResponder(overlay)
        installDictionaryDismissMonitor()
        installDictionaryLifecycleObservers()
        popover.lookup(text)
    }

    func handleDictionaryKeyEvent(_ event: NSEvent) -> Bool {
        guard isDictionaryInteractionActive else { return false }
        let handled = dictionaryPopover?.handleKeyEvent(event) ?? false
        if handled, event.type == .keyDown, event.charactersIgnoringModifiers == "\u{1b}",
           !isDictionaryInteractionActive {
            clearTextSelectionForVimNavigation()
        }
        return handled
    }

    func dismissDictionaryPopover(restoreFocus: Bool = true) {
        guard dictionaryPopover != nil else { return }
        dictionaryPopover?.stop()
        dictionaryPopover = nil
        if let overlay = dictionaryOverlay, let responder = window?.firstResponder as? NSView,
           responder === overlay || responder.isDescendant(of: overlay) {
            window?.makeFirstResponder(self)
        }
        dictionaryOverlay?.removeFromSuperview()
        dictionaryOverlay = nil
        if let dictionaryDismissMonitor {
            NSEvent.removeMonitor(dictionaryDismissMonitor)
            self.dictionaryDismissMonitor = nil
        }
        dictionaryLifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        dictionaryLifecycleObservers = []
        updateSelectionEndpointOverlay()
        if restoreFocus { focus() }
    }

    func updateDictionaryOverlayFrame() {
        guard let dictionaryOverlay else { return }
        let size = NSSize(width: min(600, max(1, visibleRect.width - 36)),
                          height: min(dictionaryPreferredHeight, max(1, visibleRect.height - 94)))
        dictionaryOverlay.frame = AIFloatingOverlayLayout.frame(
            in: visibleRect, size: size, backingScale: backingScale
        )
    }

    private func installDictionaryDismissMonitor() {
        dictionaryDismissMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, self.isDictionaryInteractionActive,
                  event.window === self.window,
                  self.appState == nil || self.appState?.activeReaderController === self else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            if self.dictionaryOverlay?.frame.insetBy(dx: -3, dy: -3).contains(point) != true {
                self.dismissDictionaryPopover(restoreFocus: false)
            }
            return event
        }
    }

    private func installDictionaryLifecycleObservers() {
        dictionaryLifecycleObservers = [
            NSWindow.didResignKeyNotification, NSWindow.willMiniaturizeNotification, NSWindow.willCloseNotification
        ].map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissDictionaryPopover(restoreFocus: false) }
            }
        }
        dictionaryLifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissDictionaryPopover(restoreFocus: false) }
        })
    }
}
