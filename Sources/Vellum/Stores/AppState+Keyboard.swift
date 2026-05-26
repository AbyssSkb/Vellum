@preconcurrency import AppKit
import PDFKit

extension AppState {
    func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, NSApp.modalWindow == nil else { return event }

            if self.activePDFView?.handleAIKeyEvent(event) == true {
                return nil
            }

            if self.activePDFView?.handleTextSelectionKeyEvent(event) == true {
                self.stopHeldKeyTimer()
                self.vimInput.clearPendingInput()
                return nil
            }

            guard self.shouldRoute(event) else { return event }

            return self.handleKeyEvent(event) ? nil : event
        }
    }

    func installOpenURLObserver() {
        OpenURLRelay.shared.activate { [weak self] urls in
            self?.open(urls: urls)
        }
    }

    private func shouldRoute(_ event: NSEvent) -> Bool {
        guard activePDFView?.isAIInteractionActive != true else { return false }
        guard let window = event.window, window.isVisible, !(window is NSPanel) else { return false }

        if let responder = window.firstResponder,
           responder is NSTextView || responder is NSTextField || responder is PDFOutlineKeyView || responderIsInsideAIExplanation(responder) {
            return false
        }

        return true
    }

    private func responderIsInsideAIExplanation(_ responder: NSResponder?) -> Bool {
        guard let view = responder as? NSView else { return false }

        var current: NSView? = view
        while let candidate = current {
            if candidate is AIExplanationWebView {
                return true
            }
            current = candidate.superview
        }

        return false
    }

    func handleKeyEvent(_ event: NSEvent) -> Bool {
        if event.type == .keyDown, handleControlJump(event) {
            return true
        }

        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return false
        }

        guard let key = event.charactersIgnoringModifiers, !key.isEmpty else { return false }

        if activePDFView?.handleTextSelectionKey(key, eventType: event.type) == true {
            stopHeldKeyTimer()
            vimInput.clearPendingInput()
            return true
        }

        switch event.type {
        case .keyDown:
            return handleKeyDown(key, isRepeat: event.isARepeat)
        case .keyUp:
            return handleKeyUp(key)
        default:
            return false
        }
    }

    private func handleControlJump(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.control),
              event.modifierFlags.intersection([.command, .option]).isEmpty else { return false }

        let key = event.charactersIgnoringModifiers?.lowercased()
        if key == "o" || event.keyCode == 31 {
            stopHeldKeyTimer()
            vimInput.clearPendingInput()
            handleVimCommand(.jumpBack)
            return true
        }

        if key == "i" || event.keyCode == 34 {
            stopHeldKeyTimer()
            vimInput.clearPendingInput()
            handleVimCommand(.jumpForward)
            return true
        }

        return false
    }

    private func handleKeyDown(_ key: String, isRepeat: Bool) -> Bool {
        if activePDFView?.handleTextSelectionKey(key, eventType: .keyDown) == true {
            stopHeldKeyTimer()
            vimInput.clearPendingInput()
            return true
        }

        if VimKeyMap.normalizedContinuousKey(key) == "d",
           activePDFView?.vimDeleteHighlightsForSelection() == true {
            stopHeldKeyTimer()
            vimInput.beginHeldKey("d")
            vimInput.clearPendingInput()
            return true
        }

        return applyVimInputAction(
            vimInput.handleKeyDown(
                key,
                isRepeat: isRepeat,
                hasNavigableTextSelection: activePDFView?.hasNavigableTextSelection == true
            )
        )
    }

    private func handleKeyUp(_ key: String) -> Bool {
        applyVimInputAction(vimInput.handleKeyUp(key))
    }

    private func ensureHeldKeyTimer() {
        guard heldKeyTimer?.isValid != true else { return }

        let timer = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            MainActor.assumeIsolated {
                guard self.vimInput.heldKey != nil else {
                    self.stopHeldKeyTimer()
                    return
                }
                self.performContinuousKey(self.vimInput.heldKey)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heldKeyTimer = timer
    }

    private func stopHeldKeyTimer() {
        heldKeyTimer?.invalidate()
        heldKeyTimer = nil
        vimInput.clearHeldKey()
    }

    private func performContinuousKey(_ key: String?) {
        guard let key else { return }

        if activePDFView?.handleTextSelectionKey(key, eventType: .keyDown) == true {
            return
        }

        if let command = VimKeyMap.continuousCommand(for: key) {
            handleVimCommand(command)
        }
    }

    private func applyVimInputAction(_ action: VimInputAction) -> Bool {
        switch action {
        case .ignored:
            return false
        case .handled:
            return true
        case .command(let command):
            handleVimCommand(command)
            return true
        case .continuousKey(let key):
            performContinuousKey(key)
            ensureHeldKeyTimer()
            return true
        case .stopContinuousKey:
            stopHeldKeyTimer()
            return true
        }
    }
}
