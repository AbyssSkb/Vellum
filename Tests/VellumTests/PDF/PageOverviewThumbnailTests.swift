@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@Suite("Page overview thumbnails")
struct PageOverviewThumbnailTests {
    @Test
    @MainActor
    func retinaThumbnailKeepsFinePDFDetailAtItsActualPixelSize() async throws {
        let document = try #require(PDFDocument(data: Self.makePDFData(pageCount: 1, drawFineLine: true)))
        let loader = PageOverviewThumbnailLoader()
        await withCheckedContinuation { continuation in
            loader.update(document: document, pageIndexes: [0], selectedIndex: 0,
                          maximumPixelSize: NSSize(width: 1224, height: 1584)) { continuation.resume() }
        }
        let image = try #require(loader.images[0])
        let bitmap = try #require(image.representations.first as? NSBitmapImageRep)
        #expect(bitmap.pixelsWide == 1224)
        #expect(bitmap.pixelsHigh == 1584)
        // A half-point PDF line is one black pixel at 2x, with white neighbors.
        // A low-resolution snapshot scaled up to Retina blurs it across two gray pixels.
        let line = try #require(bitmap.colorAt(x: 100, y: 1400)?.usingColorSpace(.sRGB))
        let left = try #require(bitmap.colorAt(x: 99, y: 1400)?.usingColorSpace(.sRGB))
        let right = try #require(bitmap.colorAt(x: 101, y: 1400)?.usingColorSpace(.sRGB))
        #expect(line.redComponent < 0.1)
        #expect(left.redComponent > 0.9)
        #expect(right.redComponent > 0.9)
    }

    @Test
    @MainActor
    func increasingDisplayPixelsUpgradesCachedImagesAndSmallerViewsReuseThem() async throws {
        let document = try #require(PDFDocument(data: Self.makePDFData(pageCount: 1)))
        let queue = OperationQueue()
        let loader = PageOverviewThumbnailLoader(queue: queue)
        await withCheckedContinuation { continuation in
            loader.update(document: document, pageIndexes: [0], selectedIndex: 0,
                          maximumPixelSize: NSSize(width: 612, height: 792)) { continuation.resume() }
        }
        let original = try #require(loader.images[0])
        await withCheckedContinuation { continuation in
            loader.update(document: document, pageIndexes: [0], selectedIndex: 0,
                          maximumPixelSize: NSSize(width: 1224, height: 1584)) { continuation.resume() }
            // Keep the previous preview visible while its larger replacement is generated.
            #expect(loader.images[0] === original)
        }
        let upgraded = try #require(loader.images[0])
        #expect(upgraded !== original)
        #expect(upgraded.representations.first?.pixelsWide == 1224)
        #expect(upgraded.representations.first?.pixelsHigh == 1584)

        for size in [NSSize(width: 1224, height: 1584), NSSize(width: 612, height: 792)] {
            loader.update(document: document, pageIndexes: [0], selectedIndex: 0, maximumPixelSize: size) {
                Issue.record("An adequate cached thumbnail was rendered again")
            }
            Self.finishBackgroundWork(in: queue)
            await drainMainQueue()
            #expect(loader.images[0] === upgraded)
        }
    }

    @Test
    @MainActor
    func renderingUsesAnIndependentPageOffMainWithCurrentCropAndRotation() async throws {
        let data = try Self.makePDFData(pageCount: 1)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("overview-\(UUID()).pdf")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try #require(PDFDocument(url: url))
        let livePage = try #require(document.page(at: 0))
        let livePageID = ObjectIdentifier(livePage)
        let crop = NSRect(x: 20, y: 30, width: 500, height: 200)
        livePage.setBounds(crop, for: .cropBox)
        livePage.rotation = 90
        livePage.addAnnotation(PDFAnnotation(
            bounds: NSRect(x: 40, y: 50, width: 80, height: 20),
            forType: .highlight,
            withProperties: nil
        ))
        let loader = PageOverviewThumbnailLoader { page, size in
            #expect(!Thread.isMainThread)
            #expect(ObjectIdentifier(page) != livePageID)
            #expect(page.rotation == 90)
            #expect(page.bounds(for: .cropBox) == crop)
            #expect(page.annotations.count == 1)
            #expect(abs(size.width - 252) < 0.001)
            #expect(abs(size.height - 630) < 0.001)
            return page.thumbnail(of: size, for: .cropBox)
        }

        await withCheckedContinuation { continuation in
            loader.update(document: document, pageIndexes: [0], selectedIndex: 0, maximumPixelSize: NSSize(width: 960, height: 630)) {
                continuation.resume()
            }
        }

        let image = try #require(loader.images[0])
        #expect(abs(image.size.width / image.size.height - 0.4) < 0.01)
        #expect(livePage.rotation == 90)
        #expect(livePage.bounds(for: .cropBox) == crop)
    }

    @Test
    @MainActor
    func currentHighlightsKeepNativeNotesPopupsAndLinks() async throws {
        let original = try #require(PDFDocument(data: Self.makePDFData(pageCount: 1)))
        let originalPage = try #require(original.page(at: 0))
        let note = PDFAnnotation(bounds: NSRect(x: 20, y: 40, width: 80, height: 12), forType: .text, withProperties: nil)
        note.contents = "External note"
        note.userName = "External author"
        originalPage.addAnnotation(note)
        let popup = try #require(note.popup)
        popup.bounds = NSRect(x: 123, y: 234, width: 301, height: 201)
        popup.setBoolean(true, forAnnotationKey: .open)
        note.popup = popup
        let link = PDFAnnotation(bounds: NSRect(x: 50, y: 60, width: 90, height: 15), forType: .link, withProperties: nil)
        link.url = URL(string: "https://example.com/document")
        originalPage.addAnnotation(link)
        let highlight = PDFAnnotation(bounds: NSRect(x: 80, y: 100, width: 120, height: 16), forType: .highlight, withProperties: nil)
        highlight.contents = "Saved highlight"
        originalPage.addAnnotation(highlight)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("overview-annotations-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try #require(original.write(to: url))
        let document = try #require(PDFDocument(url: url))
        let page = try #require(document.page(at: 0))
        let savedPopup = try #require(page.annotations.first { $0.type == "Popup" })
        let popupBounds = savedPopup.bounds
        let popupIsOpen = (savedPopup.value(forAnnotationKey: .open) as? NSNumber)?.boolValue
        let popupCount = page.annotations.filter { $0.type == "Popup" }.count
        let annotationCount = page.annotations.count
        let savedHighlight = try #require(page.annotations.first { $0.type == "Highlight" })
        savedHighlight.contents = "Current highlight"
        let loader = PageOverviewThumbnailLoader { page, size in
            #expect(page.annotations.filter { $0.type == "Text" }.count == 1)
            #expect(page.annotations.filter { $0.type == "Popup" }.count == popupCount)
            #expect(page.annotations.count == annotationCount)
            #expect(page.annotations.first { $0.type == "Text" }?.contents == "External note")
            #expect(page.annotations.first { $0.type == "Text" }?.userName == "External author")
            let popup = page.annotations.first { $0.type == "Popup" }
            #expect(popup?.bounds == popupBounds)
            #expect((popup?.value(forAnnotationKey: .open) as? NSNumber)?.boolValue == popupIsOpen)
            #expect(page.annotations.first { $0.type == "Link" }?.url == URL(string: "https://example.com/document"))
            #expect(page.annotations.filter { $0.type == "Highlight" }.count == 1)
            #expect(page.annotations.first { $0.type == "Highlight" }?.contents == "Current highlight")
            return NSImage(size: size)
        }
        await withCheckedContinuation { continuation in
            loader.update(document: document, pageIndexes: [0], selectedIndex: 0, maximumPixelSize: NSSize(width: 960, height: 630)) { continuation.resume() }
        }
        #expect(loader.images[0] != nil)
    }

    @Test
    @MainActor
    func unlockedEncryptedDocumentsRenderIndependentCopiesWithTheirPermissions() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("overview-encrypted-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let didWrite = try await Task.detached {
            let original = try #require(PDFDocument(data: Self.makePDFData(pageCount: 1)))
            let originalPage = try #require(original.page(at: 0))
            let highlight = PDFAnnotation(
                bounds: NSRect(x: 40, y: 50, width: 80, height: 20),
                forType: .highlight,
                withProperties: nil
            )
            highlight.contents = "Saved encrypted highlight"
            originalPage.addAnnotation(highlight)
            let note = PDFAnnotation(bounds: NSRect(x: 20, y: 40, width: 80, height: 12), forType: .text, withProperties: nil)
            note.contents = "Encrypted external note"
            note.userName = "External author"
            originalPage.addAnnotation(note)
            let popup = try #require(note.popup)
            popup.bounds = NSRect(x: 123, y: 234, width: 301, height: 201)
            popup.setBoolean(true, forAnnotationKey: .open)
            note.popup = popup
            return original.write(to: url, withOptions: [
                .ownerPasswordOption: "owner",
                .userPasswordOption: "reader",
                // Allow annotations while keeping copying and page assembly restricted.
                .accessPermissionsOption: NSNumber(value: 1 << 6)
            ])
        }.value
        try #require(didWrite)
        let document = try #require(PDFDocument(url: url))
        #expect(document.isLocked)
        try #require(document.unlock(withPassword: "reader"))
        let livePage = try #require(document.page(at: 0))
        let liveHighlight = try #require(livePage.annotations.first { $0.type == "Highlight" })
        #expect(liveHighlight.contents == "Saved encrypted highlight")
        liveHighlight.contents = "Current encrypted highlight"
        #expect(liveHighlight.contents == "Current encrypted highlight")
        let liveHighlightID = ObjectIdentifier(liveHighlight)
        let livePopup = try #require(livePage.annotations.first { $0.type == "Popup" })
        let popupBounds = livePopup.bounds
        let popupIsOpen = (livePopup.value(forAnnotationKey: .open) as? NSNumber)?.boolValue
        let popupCount = livePage.annotations.filter { $0.type == "Popup" }.count
        let annotationCount = livePage.annotations.count
        let livePageID = ObjectIdentifier(livePage)
        let liveDocumentID = ObjectIdentifier(document)
        let permissions = document.accessPermissions.rawValue
        let status = document.permissionsStatus.rawValue
        let allowsCopying = document.allowsCopying
        #expect(!allowsCopying)
        #expect(document.allowsCommenting)
        #expect(!document.allowsDocumentAssembly)
        let loader = PageOverviewThumbnailLoader { page, size in
            #expect(!Thread.isMainThread)
            #expect(ObjectIdentifier(page) != livePageID)
            #expect(page.annotations.count == annotationCount)
            #expect(page.annotations.first { $0.type == "Highlight" }?.contents == "Current encrypted highlight")
            #expect(page.annotations.first { $0.type == "Highlight" }.map { ObjectIdentifier($0) } != liveHighlightID)
            #expect(page.annotations.first { $0.type == "Text" }?.contents == "Encrypted external note")
            #expect(page.annotations.first { $0.type == "Text" }?.userName == "External author")
            #expect(page.annotations.filter { $0.type == "Popup" }.count == popupCount)
            let popup = page.annotations.first { $0.type == "Popup" }
            #expect(popup?.bounds == popupBounds)
            #expect((popup?.value(forAnnotationKey: .open) as? NSNumber)?.boolValue == popupIsOpen)
            if let independentDocument = page.document {
                #expect(ObjectIdentifier(independentDocument) != liveDocumentID)
                #expect(independentDocument.isEncrypted)
                #expect(!independentDocument.isLocked)
                #expect(independentDocument.accessPermissions.rawValue == permissions)
                #expect(independentDocument.permissionsStatus.rawValue == status)
                #expect(independentDocument.allowsCopying == allowsCopying)
            } else {
                Issue.record("The copied page lost its independent encrypted document")
            }
            return page.thumbnail(of: size, for: .cropBox)
        }

        await withCheckedContinuation { continuation in
            loader.update(document: document, pageIndexes: [0], selectedIndex: 0, maximumPixelSize: NSSize(width: 960, height: 630)) {
                continuation.resume()
            }
        }

        #expect(loader.images[0] != nil)
        #expect(document.isEncrypted)
        #expect(!document.isLocked)
        #expect(document.accessPermissions.rawValue == permissions)
        #expect(PDFDocument(url: url)?.isLocked == true)
    }

    @Test
    @MainActor
    func browsingManyPagesKeepsOnlyNearbyThumbnails() async throws {
        let document = try #require(PDFDocument(data: Self.makePDFData(pageCount: 24)))
        let loader = PageOverviewThumbnailLoader { _, size in NSImage(size: size) }
        for index in 0..<24 {
            await withCheckedContinuation { continuation in
                loader.update(document: document, pageIndexes: [index], selectedIndex: index, maximumPixelSize: NSSize(width: 960, height: 630)) {
                    continuation.resume()
                }
            }
            #expect(loader.images.count <= 9)
        }

        #expect(loader.images.keys.sorted() == Array(19..<24))
    }

    @Test(arguments: [false, true])
    @MainActor
    func movementAndDismissalDropCompletedResultsWaitingForDelivery(dismiss: Bool) async throws {
        let document = try #require(PDFDocument(data: Self.makePDFData(pageCount: 2)))
        let queue = OperationQueue()
        let loader = PageOverviewThumbnailLoader(queue: queue) { _, size in
            #expect(!Thread.isMainThread)
            return NSImage(size: size)
        }
        loader.update(document: document, pageIndexes: [0], selectedIndex: 0, maximumPixelSize: NSSize(width: 960, height: 630)) {
            Issue.record("A stale thumbnail reached the overview")
        }
        // Keep only main delivery pending; the worker returns and releases PDFKit resources.
        Self.finishBackgroundWork(in: queue)

        if dismiss {
            loader.cancel()
            await drainMainQueue()
            #expect(loader.images.isEmpty)
        } else {
            await withCheckedContinuation { continuation in
                loader.update(document: document, pageIndexes: [1], selectedIndex: 1, maximumPixelSize: NSSize(width: 960, height: 630)) {
                    continuation.resume()
                }
            }
            #expect(loader.images[0] == nil)
            #expect(loader.images[1] != nil)
        }
    }

    private static func finishBackgroundWork(in queue: OperationQueue) {
        queue.waitUntilAllOperationsAreFinished()
    }

    @MainActor
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private static func makePDFData(pageCount: Int, drawFineLine: Bool = false) throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            if drawFineLine {
                context.setFillColor(NSColor.black.cgColor)
                context.fill(CGRect(x: 50, y: 50, width: 0.5, height: 100))
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
