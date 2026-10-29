extension AppState {
    func showHighlights() {
        guard hasOpenTabs, let reader = activeReaderController else { return }
        highlightItems = reader.highlightListItems()
        guard !highlightItems.isEmpty else {
            showNotification(AppUILanguage.saved().text(.noHighlightsInFile), kind: .warning)
            return
        }
        rememberFocusBeforeSwitcher()
        isHighlightsPresented = true
    }

    func hideHighlights() {
        isHighlightsPresented = false
        highlightItems = []
        restoreFocusAfterSwitcher()
    }

    func openHighlight(_ item: HighlightListItem) {
        guard isHighlightsPresented, highlightItems.contains(where: { $0.id == item.id }) else { return }
        isHighlightsPresented = false
        highlightItems = []
        responderBeforeSwitcher = nil
        tabBeforeSwitcher = nil
        focusReaderContent()
        activeReaderController?.vimSelectHighlight(item)
    }

    func nextHighlight() {
        activeReaderController?.vimNavigateHighlight(1)
    }

    func previousHighlight() {
        activeReaderController?.vimNavigateHighlight(-1)
    }
}
