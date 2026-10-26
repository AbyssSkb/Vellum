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

        dictionaryAccessTask?.cancel()
        dictionaryAccessCompletion = nil
        if let dictionaryPopover {
            dictionaryPopover.lookup(text)
            return
        }

        guard let location = AppPreferences.dictionaryLocation() else {
            presentDictionaryLookup(text)
            return
        }
        let document = document
        installDictionaryLifecycleObservers(observeFocus: false)
        dictionaryAccessTask = Task { [weak self, weak window] in
            await DictionaryStore.shared.requestAccess(at: location)
            guard !Task.isCancelled, let self else { return }
            self.dictionaryAccessTask = nil
            self.dictionaryAccessCompletion = { [weak self, weak window] in
                guard let self else { return }
                guard let window, self.window === window, self.document === document,
                      self.appState == nil || self.appState?.activeReaderController === self,
                      AppPreferences.dictionaryLocation() == location,
                      AISelectedTextNormalizer.normalized(self.currentSelection?.string ?? "") == text,
                      window.isVisible, !window.isMiniaturized, window.attachedSheet == nil else {
                    self.dismissDictionaryPopover(restoreFocus: false)
                    return
                }
                // Consent can finish before AppKit restores the reader's key window.
                guard NSApp.isActive, window.isKeyWindow else { return }
                self.dictionaryAccessCompletion = nil
                self.presentDictionaryLookup(text)
            }
            self.dictionaryAccessCompletion?()
        }
    }

    private func presentDictionaryLookup(_ text: String) {
        guard let window else { return }

        let popover: DictionaryPopoverView
        if let reusable = DictionaryPopoverView.reusable,
           reusable.location == AppPreferences.dictionaryLocation() {
            popover = reusable
        } else {
            popover = DictionaryPopoverView()
        }
        DictionaryPopoverView.reusable = nil
        popover.onDismiss = { [weak self] in self?.dismissDictionaryPopover() }
        popover.onPreferredHeightChange = { [weak self, weak popover] height in
            guard let self, let popover, self.dictionaryPopover === popover else { return }
            self.dictionaryPreferredHeight = height
            self.updateDictionaryOverlayFrame()
            self.dictionaryOverlay?.layoutSubtreeIfNeeded()
        }
        popover.onLoadingChange = { [weak self, weak popover] loading in
            guard let self, let popover, self.dictionaryPopover === popover else { return }
            if !loading { self.dictionaryOverlay?.layoutSubtreeIfNeeded() }
            // Keep WebKit visible to its renderer while preparing the first painted frame.
            self.dictionaryOverlay?.alphaValue = loading ? 0 : 1
        }
        let overlay = AIFloatingOverlayContainerView(contentView: popover)
        dictionaryPopover = popover
        dictionaryOverlay = overlay
        popover.lookup(text)
        dictionaryPreferredHeight = popover.preferredHeight
        updateDictionaryOverlayFrame()
        addSubview(overlay)
        selectionEndpointOverlay?.isHidden = true
        window.makeFirstResponder(overlay)
        installDictionaryDismissMonitor()
        installDictionaryLifecycleObservers()
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
        dictionaryAccessTask?.cancel()
        dictionaryAccessTask = nil
        dictionaryAccessCompletion = nil
        dictionaryLifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        dictionaryLifecycleObservers = []
        guard dictionaryPopover != nil else { return }
        dictionaryPopover?.stop()
        DictionaryPopoverView.reusable = dictionaryPopover
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

    private func installDictionaryLifecycleObservers(observeFocus: Bool = true) {
        dictionaryLifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        let names: [Notification.Name] = [NSWindow.willMiniaturizeNotification, NSWindow.willCloseNotification]
            + (observeFocus ? [NSWindow.didResignKeyNotification] : [])
        dictionaryLifecycleObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissDictionaryPopover(restoreFocus: false) }
            }
        }
        guard observeFocus else {
            for name in [NSApplication.didBecomeActiveNotification, NSWindow.didBecomeKeyNotification] {
                dictionaryLifecycleObservers.append(NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] notification in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if let keyWindow = notification.object as? NSWindow, keyWindow !== self.window {
                            self.dismissDictionaryPopover(restoreFocus: false)
                        } else {
                            self.dictionaryAccessCompletion?()
                        }
                    }
                })
            }
            return
        }
        dictionaryLifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissDictionaryPopover(restoreFocus: false) }
        })
    }
}
