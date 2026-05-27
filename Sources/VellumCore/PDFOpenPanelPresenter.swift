@preconcurrency import AppKit
import UniformTypeIdentifiers

enum PDFOpenPanelPresenter {
    @MainActor
    static func present(
        mode: PDFOpenMode,
        completion: @escaping @MainActor ([URL]) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = mode == .newTabs
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in
                completion(panel.urls)
            }
        }
    }
}
