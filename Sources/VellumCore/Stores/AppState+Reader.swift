@preconcurrency import AppKit

extension AppState {
    func setActiveReaderController(_ controller: ReaderController?, for tabID: PDFTab.ID) {
        guard tabID == selectedTabID else { return }
        activeReaderController = controller
    }

    func snapshotForSelectedTab() -> ReaderSnapshot? {
        tabStore.snapshotForSelectedTab()
    }

    func saveSnapshot(_ snapshot: ReaderSnapshot, for tabID: PDFTab.ID) {
        tabStore.saveSnapshot(snapshot, for: tabID)
        saveCurrentSession()
    }

    public func saveActiveReaderState() {
        guard let activeReaderController,
              let selectedTabID,
              let snapshot = activeReaderController.snapshot() else { return }
        saveSnapshot(snapshot, for: selectedTabID)
    }

    func prepareForSelectedReaderChange() {
        activeReaderController = nil
        keyboardController.cancelInput()
        focusActiveReaderSoon()
    }

    var hasBlockingReaderPresentation: Bool {
        isTabSwitcherPresented || isAIConversationHistoryPresented || isAIExplanationHistoryPresented
            || NSApp?.modalWindow != nil || readerWindow?.attachedSheet != nil
    }

    var canFocusReaderContent: Bool {
        !hasBlockingReaderPresentation && readerWindow?.isKeyWindow != false
    }

    func rememberFocusBeforeSwitcher() {
        keyboardController.cancelInput()
        if !isTabSwitcherPresented && !isAIConversationHistoryPresented && !isAIExplanationHistoryPresented {
            let responder = readerWindow?.firstResponder
            if let editor = responder as? NSTextView, editor.isFieldEditor,
               let field = editor.delegate as? NSTextField {
                responderBeforeSwitcher = field
            } else {
                responderBeforeSwitcher = responder
            }
            tabBeforeSwitcher = selectedTabID
        }
    }

    func restoreFocusAfterSwitcher() {
        focusActiveReaderSoon(restoring: responderBeforeSwitcher, from: tabBeforeSwitcher)
        responderBeforeSwitcher = nil
        tabBeforeSwitcher = nil
    }

    func focusActiveReaderSoon(restoring responder: NSResponder? = nil, from sourceTabID: PDFTab.ID? = nil) {
        let tabID = selectedTabID
        let documentID = selectedTab?.document.map(ObjectIdentifier.init)
        let generation = outlineFocusGeneration
        let sourceWindow = readerWindow
        let initiatingResponder = sourceWindow?.firstResponder
        DispatchQueue.main.async { [weak self, weak responder, weak sourceWindow, weak initiatingResponder] in
            guard let self, self.selectedTabID == tabID,
                  self.selectedTab?.document.map(ObjectIdentifier.init) == documentID,
                  self.readerWindow === sourceWindow,
                  self.outlineFocusGeneration == generation,
                  self.canFocusReaderContent else { return }
            if let current = sourceWindow?.firstResponder as? NSView,
               current !== initiatingResponder, current.window === sourceWindow {
                return
            }
            if sourceTabID == tabID, let view = responder as? NSView,
               let window = self.readerWindow, view.window === window,
               !(view is PDFOutlineKeyView) || self.isOutlineVisible,
               window.makeFirstResponder(view) {
                return
            }
            if self.isOutlineVisible {
                self.focusOutlineSidebar()
            } else {
                self.activeReaderController?.focus()
            }
        }
    }

    func focusReaderSoon() {
        let tabID = selectedTabID
        let documentID = selectedTab?.document.map(ObjectIdentifier.init)
        let generation = outlineFocusGeneration
        let sourceWindow = readerWindow
        let initiatingResponder = sourceWindow?.firstResponder
        DispatchQueue.main.async { [weak self, weak sourceWindow, weak initiatingResponder] in
            guard let self, self.selectedTabID == tabID,
                  self.selectedTab?.document.map(ObjectIdentifier.init) == documentID,
                  self.readerWindow === sourceWindow,
                  self.outlineFocusGeneration == generation,
                  !self.isOutlineVisible, self.canFocusReaderContent else { return }
            if let current = sourceWindow?.firstResponder as? NSView,
               current !== initiatingResponder, current.window === sourceWindow {
                return
            }
            self.activeReaderController?.focus()
        }
    }
}
