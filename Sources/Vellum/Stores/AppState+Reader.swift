import Foundation

extension AppState {
    func setActivePDFView(_ view: VellumPDFView?, for tabID: PDFTab.ID) {
        guard tabID == selectedTabID else { return }
        activePDFView = view
    }

    func snapshotForSelectedTab() -> ReaderSnapshot? {
        tabStore.snapshotForSelectedTab()
    }

    func saveSnapshot(_ snapshot: ReaderSnapshot, for tabID: PDFTab.ID) {
        tabStore.saveSnapshot(snapshot, for: tabID)
    }

    func saveActiveReaderState() {
        guard let activePDFView,
              let selectedTabID,
              let snapshot = activePDFView.snapshot() else { return }
        saveSnapshot(snapshot, for: selectedTabID)
    }

    func focusActivePDFViewSoon() {
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
            self?.activePDFView?.focus()
        }
    }
}
