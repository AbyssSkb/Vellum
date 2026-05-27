import Foundation

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
    }

    func saveActiveReaderState() {
        guard let activeReaderController,
              let selectedTabID,
              let snapshot = activeReaderController.snapshot() else { return }
        saveSnapshot(snapshot, for: selectedTabID)
    }

    func prepareForSelectedReaderChange() {
        activeReaderController = nil
        focusActiveReaderSoon()
    }

    func focusActiveReaderSoon() {
        if isOutlineVisible {
            DispatchQueue.main.async { [weak self] in
                self?.outlineFocusGeneration += 1
            }
            return
        }
        focusReaderSoon()
    }

    func focusReaderSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.activeReaderController?.focus()
        }
    }
}
