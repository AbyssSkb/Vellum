@preconcurrency import AppKit
import UniformTypeIdentifiers

enum PDFOpenPanelPresenter {
    @MainActor
    static func present(
        mode: PDFOpenMode,
        completion: @escaping @MainActor ([URL]) -> Void
    ) {
        let panel = NSOpenPanel()
        let markdownTypes = [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            UTType(filenameExtension: "mdown")
        ].compactMap { $0 }
        panel.allowedContentTypes = [.pdf] + markdownTypes
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
