import AppKit
import PDFKit
import UniformTypeIdentifiers

extension AppState {
    func canCloseTab(_ id: PDFTab.ID) -> Bool {
        guard let document = tabs.first(where: { $0.id == id })?.document else { return true }
        PDFAnnotationPersistence.existing(for: document)?.onPrepareToClose?()
        return resolveAnnotationFailure(for: document)
    }

    public func prepareToTerminate() -> Bool {
        prepareToTerminate(resolving: canCloseTab)
    }

    func prepareToTerminate(resolving resolve: (PDFTab.ID) -> Bool) -> Bool {
        repeat {
            for tab in tabs where !resolve(tab.id) { return false }
        } while hasUnprotectedAnnotations
        saveActiveReaderState()
        saveCurrentSession()
        return !hasUnprotectedAnnotations
    }

    private var hasUnprotectedAnnotations: Bool {
        tabs.contains { tab in
            guard let document = tab.document else { return false }
            return PDFAnnotationPersistence.existing(for: document)?.hasUnprotectedChanges == true
        }
    }

    @discardableResult
    func resolveAnnotationFailure(for document: PDFDocument) -> Bool {
        guard tabs.contains(where: { $0.document === document }) else { return true }
        guard let persistence = PDFAnnotationPersistence.existing(for: document) else { return true }
        persistence.flush()
        guard persistence.hasUnprotectedChanges else { return true }
        guard !persistence.isPresentingRecovery else { return false }
        persistence.isPresentingRecovery = true
        defer { persistence.isPresentingRecovery = false }
        while persistence.hasUnprotectedChanges {
            let language = AppUILanguage.saved()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = language.text(.annotationSaveFailed(document.documentURL?.lastPathComponent ?? "PDF"))
            alert.informativeText = (persistence.failure ?? .unreadable).message
            alert.addButton(withTitle: language.text(.annotationSaveRetry))
            alert.addButton(withTitle: language.text(.annotationSaveCopy))
            alert.addButton(withTitle: language.text(.cancel))
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                persistence.retry(document)
            case .alertSecondButtonReturn:
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.pdf]
                panel.nameFieldStringValue = (document.documentURL?.deletingPathExtension().lastPathComponent ?? "PDF") + " (2).pdf"
                guard panel.runModal() == .OK, let url = panel.url else { continue }
                do {
                    try persistence.saveCopy(document, to: url)
                } catch {
                    let copyAlert = NSAlert()
                    copyAlert.alertStyle = .warning
                    copyAlert.messageText = language.text(.annotationSaveCopyFailed)
                    copyAlert.informativeText = (error as? PDFAnnotationPersistence.SaveError)?.message ?? error.localizedDescription
                    copyAlert.addButton(withTitle: language.text(.cancel))
                    copyAlert.runModal()
                }
            default:
                return false
            }
        }
        return true
    }
}
