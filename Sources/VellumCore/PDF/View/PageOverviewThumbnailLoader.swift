@preconcurrency import AppKit
@preconcurrency import PDFKit

@MainActor
final class PageOverviewThumbnailLoader {
    // The unlocked copy belongs only to the serial thumbnail worker after capture.
    private struct Source: @unchecked Sendable {
        let url: URL?
        let unlockedDocument: PDFDocument?
    }

    // Vellum edits highlights; other annotations remain in the independent PDF.
    private struct Request: @unchecked Sendable {
        let index: Int
        let rotation: Int
        let mediaBounds: CGRect
        let cropBounds: CGRect
        let highlights: [PDFAnnotation]
        let popups: [PDFPopupSnapshot]
        let data: Data?
    }

    private let queue: OperationQueue
    private let render: @Sendable (PDFPage, NSSize) -> NSImage
    private var generation = 0
    private(set) var images: [Int: NSImage] = [:]

    init(
        queue: OperationQueue = OperationQueue(),
        render: @escaping @Sendable (PDFPage, NSSize) -> NSImage = { page, size in
            page.thumbnail(of: size, for: .cropBox)
        }
    ) {
        self.queue = queue
        self.render = render
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
    }

    deinit {
        queue.cancelAllOperations()
    }

    func update(
        document: PDFDocument,
        pageIndexes: [Int],
        selectedIndex: Int,
        didLoad: @escaping @MainActor @Sendable () -> Void
    ) {
        cancel()
        // Retain at most nine nearby pages while moving through a long document.
        images = images.filter { abs($0.key - selectedIndex) <= 4 }
        let url = document.documentURL
        let requests = pageIndexes.compactMap { index -> Request? in
            guard abs(index - selectedIndex) <= 4,
                  images[index] == nil,
                  let page = document.page(at: index) else { return nil }
            return Request(
                index: index,
                rotation: page.rotation,
                mediaBounds: page.bounds(for: .mediaBox),
                cropBounds: page.bounds(for: .cropBox),
                highlights: page.annotations.filter { $0.type == "Highlight" }.compactMap {
                    guard let copy = $0.copy() as? PDFAnnotation else { return nil }
                    copy.page = nil
                    return copy
                },
                popups: PDFPopupSnapshot.capture(from: page),
                // In-memory documents need only the requested page, never the entire PDF.
                data: url == nil && !document.isEncrypted ? page.dataRepresentation : nil
            )
        }
        guard !requests.isEmpty else { return }
        let source = Source(
            url: url,
            unlockedDocument: document.isEncrypted && !document.isLocked ? document.copy() as? PDFDocument : nil
        )

        let currentGeneration = generation
        let renderer = render
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard operation?.isCancelled == false else { return }
            let independentDocument = source.unlockedDocument ?? source.url.flatMap { PDFDocument(url: $0) }
            for request in requests {
                guard operation?.isCancelled == false else { return }
                let image: NSImage? = autoreleasepool {
                    let pageDocument = request.data.flatMap { PDFDocument(data: $0) } ?? independentDocument
                    guard let page = pageDocument?.page(at: request.data == nil ? request.index : 0) else {
                        return nil
                    }
                    guard PDFPopupSnapshot.restore(request.popups, to: page) else { return nil }
                    if page.bounds(for: .mediaBox) != request.mediaBounds {
                        page.setBounds(request.mediaBounds, for: .mediaBox)
                    }
                    if page.bounds(for: .cropBox) != request.cropBounds {
                        page.setBounds(request.cropBounds, for: .cropBox)
                    }
                    if page.rotation != request.rotation {
                        page.rotation = request.rotation
                    }
                    for annotation in page.annotations where annotation.type == "Highlight" {
                        page.removeAnnotation(annotation)
                    }
                    for highlight in request.highlights { page.addAnnotation(highlight) }

                    let size = PDFPageDisplayGeometry(page: page, box: .cropBox).bounds.size
                    guard size.width > 0, size.height > 0 else { return nil }
                    let scale = min(960 / size.width, 630 / size.height)
                    return renderer(page, NSSize(width: size.width * scale, height: size.height * scale))
                }
                guard let image, operation?.isCancelled == false else { continue }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == currentGeneration else { return }
                    self.images[request.index] = image
                    didLoad()
                }
            }
        }
        queue.addOperation(operation)
    }

    func cancel() {
        generation &+= 1
        queue.cancelAllOperations()
    }
}
