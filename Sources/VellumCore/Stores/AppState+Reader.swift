@preconcurrency import AppKit
import PDFKit

extension AppState {
    func setActiveReaderController(_ controller: ReaderController?, for tabID: PDFTab.ID) {
        guard tabID == selectedTabID, activeReaderController !== controller else { return }
        activeReaderController = controller
        (controller as? VellumPDFView)?.scheduleReadingPositionReport()
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
        recordReadingFocusIntent(outline: isOutlineVisible && readerWindow?.firstResponder is PDFOutlineKeyView)
        activeReaderController = nil
        outlineReadingDestination = nil
        outlineReadingItemID = nil
        keyboardController.cancelInput()
        if isAIConversationHistoryPresented || isAIExplanationHistoryPresented {
            isAIConversationHistoryPresented = false
            isAIExplanationHistoryPresented = false
            restoreFocusAfterSwitcher()
        } else {
            focusActiveReaderSoon()
        }
    }

    func updateOutlineReadingPosition(
        _ destination: PDFDestination, from reader: VellumPDFView,
        userNavigated: Bool = false, pinSection: Bool = false
    ) {
        guard reader === activeReaderController, !reader.isPageOverviewActive,
              let document = selectedTab?.document, destination.page?.document === document else { return }
        if userNavigated, outlineReadingItemID != nil { outlineReadingItemID = nil }
        if pinSection {
            outlineReadingItemID = OutlineReadingMatcher.item(
                for: destination, in: PDFOutlineBuilder.items(for: document)
            )?.id
        }
        if outlineReadingDestination?.page !== destination.page
            || outlineReadingDestination?.point != destination.point {
            outlineReadingDestination = destination
        }
        if let outline = activeOutlineView,
           let coordinator = outline.delegate as? PDFOutlineView.Coordinator {
            coordinator.syncReadingPosition(in: outline)
        }
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
        let prefersOutline = isOutlineVisible && (responder ?? readerWindow?.firstResponder) is PDFOutlineKeyView
        queueReaderFocus { [weak responder] state in
            if sourceTabID == tabID, let view = responder as? NSView,
               let window = state.readerWindow, view.window === window,
               !(view is PDFOutlineKeyView) || state.isOutlineVisible,
               window.makeFirstResponder(view) {
                return
            }
            if prefersOutline, state.isOutlineVisible {
                state.focusOutlineSidebar()
            } else {
                state.focusReaderContent()
            }
        }
    }

    func focusReaderSoon() {
        queueReaderFocus { state in
            state.activeReaderController?.focus()
        }
    }

    func focusActivatedReaderSoon(_ reader: VellumPDFView) {
        guard !isOutlineVisible else { return }
        queueReaderFocus(in: reader.window, allowsInactiveWindow: true) { [weak reader] state in
            guard let reader, state.activeReaderController === reader,
                  !state.isOutlineVisible else { return }
            if reader.isAIInteractionActive {
                reader.restoreAIFloatingOverlayPresentation()
            } else {
                reader.focus()
            }
        }
    }

    private func queueReaderFocus(
        in window: NSWindow? = nil, allowsInactiveWindow: Bool = false,
        _ apply: @escaping (AppState) -> Void
    ) {
        let tabID = selectedTabID
        let documentID = selectedTab?.document.map(ObjectIdentifier.init)
        let generation = outlineFocusGeneration
        let sourceReaderWindow = readerWindow
        let sourceWindow = window ?? sourceReaderWindow
        let initiatingResponder = sourceWindow?.firstResponder
        DispatchQueue.main.async { [weak self, weak sourceReaderWindow, weak sourceWindow, weak initiatingResponder] in
            guard let self, self.selectedTabID == tabID,
                  self.selectedTab?.document.map(ObjectIdentifier.init) == documentID,
                  self.readerWindow === sourceReaderWindow,
                  self.outlineFocusGeneration == generation,
                  self.canFocusReaderContent || (allowsInactiveWindow && !self.hasBlockingReaderPresentation),
                  allowsInactiveWindow || sourceWindow?.isKeyWindow != false,
                  sourceWindow?.attachedSheet == nil else { return }
            if let current = sourceWindow?.firstResponder as? NSView,
               current !== initiatingResponder, current.window === sourceWindow {
                return
            }
            apply(self)
        }
    }
}
