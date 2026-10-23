import PDFKit

protocol PDFTabLoading {
    func tab(for url: URL) -> PDFTab?
}

struct PDFDocumentLoader: PDFTabLoading {
    static func failureReason(for url: URL) -> AppText {
        do {
            _ = try Data(contentsOf: url, options: .mappedIfSafe)
            return .fileUnparseable
        } catch {
            let error = error as NSError
            guard error.domain == NSCocoaErrorDomain else { return .fileCannotRead }
            switch error.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return .fileMissing
            case NSFileReadNoPermissionError:
                return .filePermissionDenied
            default:
                return .fileCannotRead
            }
        }
    }

    func tab(for url: URL) -> PDFTab? {
        let persistence = PDFAnnotationPersistence(url: url)
        guard let document = PDFDocument(url: url) else { return nil }
        PDFAnnotationPersistence.register(document, state: persistence)
        return PDFTab(url: url, document: document, snapshot: .initial)
    }
}
