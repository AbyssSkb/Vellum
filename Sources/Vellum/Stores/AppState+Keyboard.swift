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
                self.keyState.clearPendingInput()
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
            keyState.clearPendingInput()
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
            keyState.clearPendingInput()
            handleVimCommand(.jumpBack)
            return true
        }

        if key == "i" || event.keyCode == 34 {
            stopHeldKeyTimer()
            keyState.clearPendingInput()
            handleVimCommand(.jumpForward)
            return true
        }

        return false
    }

    private func handleKeyDown(_ key: String, isRepeat: Bool) -> Bool {
        if handleUppercaseCommand(key) {
            return true
        }

        if activePDFView?.handleTextSelectionKey(key, eventType: .keyDown) == true {
            stopHeldKeyTimer()
            keyState.clearPendingInput()
            return true
        }

        if VimKeyMap.normalizedContinuousKey(key) == "d",
           activePDFView?.vimDeleteHighlightsForSelection() == true {
            stopHeldKeyTimer()
            keyState.heldKey = "d"
            keyState.clearPendingInput()
            return true
        }

        guard VimKeyMap.isContinuousKey(key) else {
            if isRepeat {
                return VimKeyMap.isHandledKey(
                    key,
                    hasNavigableTextSelection: activePDFView?.hasNavigableTextSelection == true
                )
            }
            return handleKey(key)
        }

        let normalizedKey = VimKeyMap.normalizedContinuousKey(key)
        if keyState.heldKey == normalizedKey {
            return true
        }

        keyState.heldKey = normalizedKey
        performContinuousKey(keyState.heldKey)
        ensureHeldKeyTimer()
        return true
    }

    private func handleKeyUp(_ key: String) -> Bool {
        guard VimKeyMap.isContinuousKey(key),
              keyState.heldKey == VimKeyMap.normalizedContinuousKey(key) else { return false }
        stopHeldKeyTimer()
        return true
    }

    private func handleUppercaseCommand(_ key: String) -> Bool {
        switch key {
        case "G":
            if let pageNumber = consumeNumericPrefix() {
                handleVimCommand(.jumpToPage(pageNumber))
            } else {
                handleVimCommand(.lastPage)
            }
        case "H":
            keyState.numericPrefix = ""
            handleVimCommand(.previousTab)
        case "L":
            keyState.numericPrefix = ""
            handleVimCommand(.nextTab)
        case "X":
            keyState.numericPrefix = ""
            handleVimCommand(.restoreClosedTab)
        case "O":
            keyState.numericPrefix = ""
            handleVimCommand(.openInNewTab)
        default:
            return false
        }
        return true
    }

    func handleKey(_ key: String) -> Bool {
        if handleNumericPrefixKey(key) {
            return true
        }

        if keyState.pendingKey == "g" {
            keyState.clearPendingInput()
            switch key {
            case "g":
                handleVimCommand(.firstPage)
            case "t":
                handleVimCommand(.nextTab)
            case "T":
                handleVimCommand(.previousTab)
            default:
                return false
            }
            return true
        }

        if activePDFView?.vimNavigateTextSelection(key) == true {
            keyState.clearPendingInput()
            return true
        }

        switch key {
        case "g":
            keyState.numericPrefix = ""
            keyState.pendingKey = "g"
        case "G":
            if let pageNumber = consumeNumericPrefix() {
                handleVimCommand(.jumpToPage(pageNumber))
            } else {
                handleVimCommand(.lastPage)
            }
        default:
            if let command = VimKeyMap.command(for: key) {
                keyState.clearPendingInput()
                handleVimCommand(command)
                return true
            }

            keyState.numericPrefix = ""
            guard let fallback = VimKeyMap.lowercaseFallback(for: key) else { return false }
            return handleKey(fallback)
        }
        return true
    }

    private func ensureHeldKeyTimer() {
        guard heldKeyTimer?.isValid != true else { return }

        let timer = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            MainActor.assumeIsolated {
                guard self.keyState.heldKey != nil else {
                    self.stopHeldKeyTimer()
                    return
                }
                self.performContinuousKey(self.keyState.heldKey)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heldKeyTimer = timer
    }

    private func stopHeldKeyTimer() {
        heldKeyTimer?.invalidate()
        heldKeyTimer = nil
        keyState.clearHeldKey()
    }

    private func handleNumericPrefixKey(_ key: String) -> Bool {
        keyState.handleNumericPrefixKey(key)
    }

    private func consumeNumericPrefix() -> Int? {
        keyState.consumeNumericPrefix()
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

}
