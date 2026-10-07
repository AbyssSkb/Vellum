@preconcurrency import AppKit
import PDFKit
import QuartzCore
import Testing
@testable import VellumCore

@MainActor
@Suite("Page overview gallery")
struct PageOverviewGalleryTests {
    @Test
    func previewsGrowWithViewportAndKeepEachPageAspectRatio() {
        let document = PDFDocument()
        for size in [NSSize(width: 612, height: 792), NSSize(width: 842, height: 595)] {
            let page = PDFPage()
            page.setBounds(NSRect(origin: .zero, size: size), for: .mediaBox)
            document.insert(page, at: document.pageCount)
        }
        let overlay = PageOverviewOverlayView(document: document, selectedIndex: 0, columns: 3)
        overlay.setFrameSize(NSSize(width: 1000, height: 700))
        let compact = overlay.paperSize(for: 0)
        #expect(abs(compact.width / compact.height - 612.0 / 792) < 0.001)
        overlay.setFrameSize(NSSize(width: 1400, height: 1000))
        let large = overlay.paperSize(for: 0)
        let landscape = overlay.paperSize(for: 1)
        #expect(large.height > compact.height + 250)
        #expect(large.height == 896)
        #expect(abs(landscape.width / landscape.height - 842.0 / 595) < 0.001)
        #expect(landscape.width <= (1400 - 48) * 0.78)
    }

    @Test
    func entryKeepsTheVisiblePageGeometryAndNavigationKeepsPaperOpaque() async throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<3 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            document.insert(page, at: index)
        }
        let source = NSRect(x: -40, y: -180, width: 800, height: 800 * 792 / 612)
        let overlay = PageOverviewOverlayView(document: document, selectedIndex: 1, columns: 3,
                                              entryPageRect: source)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = overlay
        window.orderFront(nil)
        defer { overlay.dismiss(animated: false); window.contentView = nil; window.close() }

        var entry: CAAnimationGroup?
        for _ in 0..<50 {
            entry = overlay.layer?.sublayers?.first { $0.name == "page-1" }?
                .animation(forKey: "galleryTransition") as? CAAnimationGroup
            if entry != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let animation = try #require(entry)
        let position = try #require(animation.animations?.compactMap { $0 as? CABasicAnimation }
            .first { $0.keyPath == "position" }?.fromValue as? NSValue)
        let transform = try #require(animation.animations?.compactMap { $0 as? CABasicAnimation }
            .first { $0.keyPath == "transform" }?.fromValue as? NSValue)
        let scale = source.width / overlay.paperSize(for: 1).width
        #expect(abs(position.pointValue.x - source.midX) < 0.001)
        #expect(abs(position.pointValue.y - (source.midY - 14 * scale)) < 0.001)
        #expect(abs(transform.caTransform3DValue.m11 - scale) < 0.001)
        #expect(abs(animation.duration - 0.34) < 0.001)

        try await Task.sleep(for: .milliseconds(450))
        overlay.update(selectedIndex: 2)
        let departing = try #require(overlay.layer?.sublayers?.first { $0.name == "page-1" })
        let navigation = try #require(departing.animation(forKey: "galleryTransition") as? CAAnimationGroup)
        let keyPaths = navigation.animations?.compactMap { ($0 as? CABasicAnimation)?.keyPath } ?? []
        #expect(departing.opacity == 1)
        #expect(keyPaths.contains("shadowRadius"))
        #expect(!keyPaths.contains("zPosition"))
        let image = try #require(departing.sublayers?.first { $0.name == "thumbnail" })
        let shade = try #require(image.sublayers?.first { $0.name == "shade" })
        #expect(abs(shade.opacity - 0.13) < 0.001)
        let number = try #require(departing.sublayers?.first { $0 is CATextLayer })
        let numberGroup = try #require(number.animation(forKey: "galleryTransition") as? CAAnimationGroup)
        let numberAnimation = try #require(numberGroup.animations?.first as? CABasicAnimation)
        #expect(numberAnimation.keyPath == "opacity")
        #expect(number.opacity == 1)
    }

    @Test
    func pendingThumbnailKeepsTheCurrentPaperPastAnEarlierCleanup() async throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<8 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            document.insert(page, at: index)
        }
        let queue = OperationQueue()
        let loader = PageOverviewThumbnailLoader(queue: queue)
        let overlay = PageOverviewOverlayView(document: document, selectedIndex: 0, columns: 3,
                                              thumbnailLoader: loader)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = overlay
        window.orderFront(nil)
        defer {
            queue.isSuspended = false
            overlay.dismiss(animated: false)
            window.contentView = nil
            window.close()
        }
        let controller = PageOverviewController(overlay: overlay, originalIndex: 0,
                                              selectedIndex: 0, pageCount: 8, columns: 3)
        for _ in 0..<50 {
            if loader.images[0] != nil && loader.images[1] != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(loader.images[0] != nil && loader.images[1] != nil)
        controller.move(.next)
        controller.move(.previous)
        queue.isSuspended = true
        controller.move(.nextRow)
        try await Task.sleep(for: .milliseconds(400))
        #expect(controller.selectedIndex == 3)
        #expect(loader.images[3] == nil)
        let retained = try #require(overlay.layer?.sublayers?.first { $0.name == "page-0" })
        #expect(retained.opacity == 1)

        queue.isSuspended = false
        for _ in 0..<100 {
            let hasOldPaper = overlay.layer?.sublayers?.contains { $0.name == "page-0" } == true
            if loader.images[3] != nil && !hasOldPaper { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(loader.images[3] != nil)
        #expect(overlay.layer?.sublayers?.contains { $0.name == "page-0" } == false)
        let selected = try #require(overlay.layer?.sublayers?.first { $0.name == "page-3" })
        #expect(selected.opacity == 1)
    }

    @Test
    func rapidRowNavigationRetainsDepartingPaperAndPointerSelectionUsesController() async throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<12 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            document.insert(page, at: index)
        }
        let overlay = PageOverviewOverlayView(document: document, selectedIndex: 0, columns: 3)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = overlay
        window.orderFront(nil)
        defer { overlay.dismiss(animated: false); window.contentView = nil; window.close() }
        let controller = PageOverviewController(overlay: overlay, originalIndex: 0,
                                              selectedIndex: 0, pageCount: 12, columns: 3)
        try await Task.sleep(for: .milliseconds(350))
        controller.move(.nextRow)
        controller.move(.nextRow)
        #expect(controller.selectedIndex == 6)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            #expect(overlay.layer?.sublayers?.contains { $0.name == "page-0" } == true)
        }
        overlay.onSelectPage?(5)
        #expect(controller.selectedIndex == 5)
        overlay.onSelectPage?(-1)
        #expect(controller.selectedIndex == 0)
        overlay.onSelectPage?(99)
        #expect(controller.selectedIndex == 11)
        let preservesFocus = overlay.subviews.compactMap { $0 as? NSButton }.allSatisfy { $0.refusesFirstResponder }
        #expect(preservesFocus)
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(500))
        let paperCount = overlay.layer?.sublayers?.filter { $0.name?.hasPrefix("page-") == true }.count
        #expect(paperCount == 2)
    }
}
