@preconcurrency import AppKit
import PDFKit
import QuartzCore
import Testing
@testable import VellumCore

@MainActor
@Suite("Page overview gallery")
struct PageOverviewGalleryTests {
    @Test(arguments: [800.0, 6000.0])
    func entryResolutionOnlyUpgradesTheSelectedPage(entryWidth: Double) async throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        let pageSize = NSSize(width: 612, height: 792)
        for index in 0..<3 {
            let page = PDFPage()
            page.setBounds(NSRect(origin: .zero, size: pageSize), for: .mediaBox)
            document.insert(page, at: index)
        }
        let loader = PageOverviewThumbnailLoader { _, size in NSImage(size: size) }
        let entry = NSRect(x: -40, y: -180, width: entryWidth, height: entryWidth * 792 / 612)
        let overlay = PageOverviewOverlayView(document: document, selectedIndex: 1, columns: 3,
                                              entryPageRect: entry, thumbnailLoader: loader)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = overlay
        window.orderFront(nil)
        defer { overlay.dismiss(animated: false); window.contentView = nil; window.close() }
        try await waitForTestCondition("Selected and neighboring gallery requests complete") {
            loader.images.count == 3
        }

        let backingScale = window.backingScaleFactor
        let ordinary = overlay.paperSize(for: 1)
        let normalPixels = NSSize(width: ceil(ordinary.width * backingScale),
                                  height: ceil(ordinary.height * backingScale))
        let limit = max(overlay.bounds.width, overlay.bounds.height) * 2
        let selectedScale = min(max(ordinary.width, min(entry.width, limit)) / pageSize.width,
                                max(ordinary.height, min(entry.height, limit)) / pageSize.height) * backingScale
        let selectedPixels = NSSize(width: ceil(pageSize.width * selectedScale),
                                    height: ceil(pageSize.height * selectedScale))
        #expect(loader.images[1]?.size == selectedPixels)
        #expect(loader.images[0]?.size == normalPixels)
        #expect(loader.images[2]?.size == normalPixels)

        let original = try #require(loader.images[1])
        overlay.update(selectedIndex: 2)
        try await waitForTestCondition("Promoted neighbor gains reader-resolution detail") {
            loader.images[2]?.size == selectedPixels
        }
        let promoted = try #require(loader.images[2])
        overlay.update(selectedIndex: 2)
        await nextTestMainQueueTurn()
        #expect(loader.images[2] === promoted)
        #expect(loader.images[1] !== original)
    }

    @Test
    func browsingKeepsReaderResolutionOnlyForTheCurrentPage() async throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<8 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            document.insert(page, at: index)
        }
        let queue = OperationQueue()
        let loader = PageOverviewThumbnailLoader(queue: queue) { _, size in NSImage(size: size) }
        let overlay = PageOverviewOverlayView(document: document, selectedIndex: 0, columns: 3,
                                              entryPageRect: NSRect(x: 0, y: 0, width: 6000, height: 8000),
                                              thumbnailLoader: loader)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = overlay
        window.orderFront(nil)
        defer { overlay.dismiss(animated: false); window.contentView = nil; window.close() }
        let ordinary = overlay.paperSize(for: 0)
        let normalPixels = NSSize(width: ceil(ordinary.width * window.backingScaleFactor),
                                  height: ceil(ordinary.height * window.backingScaleFactor))

        for selectedIndex in 0...6 {
            if selectedIndex > 0 { overlay.update(selectedIndex: selectedIndex) }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                queue.addOperation { continuation.resume() }
            }
            await nextTestMainQueueTurn()
            let selected = try #require(loader.images[selectedIndex])
            #expect(selected.size.width > normalPixels.width)
            #expect(loader.images.count <= 9)
            for (index, image) in loader.images where index != selectedIndex {
                #expect(image.size == normalPixels, "Page \(index) retained reader-resolution pixels after selecting \(selectedIndex)")
            }
        }
    }

    @Test(.enabled("Requires gallery animations") {
        await MainActor.run { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    })
    func pendingReaderResolutionFadesOutWithoutEnlargingThePreview() async throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<3 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            document.insert(page, at: index)
        }
        let queue = OperationQueue()
        let loader = PageOverviewThumbnailLoader(queue: queue)
        let target = NSRect(x: -40, y: -180, width: 800, height: 800 * 792 / 612)
        let overlay = PageOverviewOverlayView(document: document, selectedIndex: 1, columns: 3,
                                              entryPageRect: target, thumbnailLoader: loader)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSView(frame: window.contentView!.bounds)
        window.contentView = host
        overlay.frame = host.bounds
        host.addSubview(overlay)
        window.orderFront(nil)
        defer {
            queue.isSuspended = false
            overlay.dismiss(animated: false)
            window.contentView = nil
            window.close()
        }
        try await waitForTestCondition("Gallery previews load before the upgrade is blocked") {
            loader.images.count == 3
        }
        queue.isSuspended = true
        overlay.update(selectedIndex: 2)
        let selected = try #require(overlay.layer?.sublayers?.first { $0.name == "page-2" })
        let image = try #require(selected.sublayers?.first { $0.name == "thumbnail" })
        try #require(image.contents != nil)
        let position = selected.position
        let transform = selected.transform

        overlay.dismiss(to: target)

        #expect(selected.position == position)
        #expect(CATransform3DEqualToTransform(selected.transform, transform))
        #expect(overlay.layer?.animation(forKey: "galleryExitFade") == nil)
        try await waitForTestCondition("Pending reader-resolution work does not delay dismissal") {
            overlay.superview == nil
        }
    }

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
        #expect(large.height > compact.height)
        #expect(large.height > overlay.bounds.height * 0.75)
        #expect(large.height < overlay.bounds.height)
        #expect(abs(landscape.width / landscape.height - 842.0 / 595) < 0.001)
        #expect(landscape.width < overlay.bounds.width)
    }

    @Test(.enabled("Requires gallery animations") {
        await MainActor.run { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    })
    func entryKeepsTheVisiblePageGeometryAndNavigationKeepsPaperOpaque() async throws {
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

        try await waitForTestCondition("Gallery entry transition starts") {
            overlay.layer?.sublayers?.first { $0.name == "page-1" }?
                .animation(forKey: "galleryTransition") is CAAnimationGroup
        }
        let paper = try #require(overlay.layer?.sublayers?.first { $0.name == "page-1" })
        let animation = try #require(paper.animation(forKey: "galleryTransition") as? CAAnimationGroup)
        let position = try #require(animation.animations?.compactMap { $0 as? CABasicAnimation }
            .first { $0.keyPath == "position" }?.fromValue as? NSValue)
        let transform = try #require(animation.animations?.compactMap { $0 as? CABasicAnimation }
            .first { $0.keyPath == "transform" }?.fromValue as? NSValue)
        let image = try #require(paper.sublayers?.first { $0.name == "thumbnail" })
        let scale = source.width / image.bounds.width
        #expect(abs(position.pointValue.x - source.midX) < 0.001)
        let imageCenterY = position.pointValue.y + (image.frame.midY - paper.bounds.midY) * scale
        #expect(abs(imageCenterY - source.midY) < 0.001)
        #expect(abs(transform.caTransform3DValue.m11 - scale) < 0.001)
        #expect(animation.duration > 0)

        // AppKit's test run loop can retain completed layer animations; advance past their observed duration.
        try await Task.sleep(for: .seconds(animation.duration + 0.05))
        await nextTestMainQueueTurn()
        overlay.update(selectedIndex: 2)
        let departing = try #require(overlay.layer?.sublayers?.first { $0.name == "page-1" })
        let navigation = try #require(departing.animation(forKey: "galleryTransition") as? CAAnimationGroup)
        let keyPaths = navigation.animations?.compactMap { ($0 as? CABasicAnimation)?.keyPath } ?? []
        #expect(departing.opacity == 1)
        #expect(keyPaths.contains("shadowRadius"))
        #expect(!keyPaths.contains("zPosition"))
        let departingImage = try #require(departing.sublayers?.first { $0.name == "thumbnail" })
        let shade = try #require(departingImage.sublayers?.first { $0.name == "shade" })
        #expect(shade.opacity > 0 && shade.opacity < 1)
        let current = try #require(overlay.layer?.sublayers?.first { $0.name == "page-2" })
        let currentImage = try #require(current.sublayers?.first { $0.name == "thumbnail" })
        #expect(currentImage.sublayers?.first { $0.name == "shade" }?.opacity == 0)
        #expect(current.zPosition > departing.zPosition)
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
        try await waitForTestCondition("Initial gallery thumbnails load") {
            loader.images[0] != nil && loader.images[1] != nil
        }
        controller.move(.next)
        controller.move(.previous)
        let earlierTransition = overlay.layer?.sublayers?.first { $0.name == "page-0" }?
            .animation(forKey: "galleryTransition")?.duration ?? 0
        queue.isSuspended = true
        controller.move(.nextRow)
        // Exercise the earlier cleanup after its deadline while replacement rendering is blocked.
        try await Task.sleep(for: .seconds(earlierTransition + 0.1))
        #expect(controller.selectedIndex == 3)
        #expect(loader.images[3] == nil)
        let retained = try #require(overlay.layer?.sublayers?.first { $0.name == "page-0" })
        #expect(retained.opacity == 1)

        queue.isSuspended = false
        try await waitForTestCondition("Replacement thumbnail retires the old paper") {
            let hasOldPaper = overlay.layer?.sublayers?.contains { $0.name == "page-0" } == true
            return loader.images[3] != nil && !hasOldPaper
        }
        let selected = try #require(overlay.layer?.sublayers?.first { $0.name == "page-3" })
        #expect(selected.opacity == 1)
    }

    @Test(.enabled("Requires gallery animations") {
        await MainActor.run { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    })
    func exitReturnsOpaquePaperToItsReaderGeometryBeforeRemovingTheOverlay() async throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<3 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            document.insert(page, at: index)
        }
        let loader = PageOverviewThumbnailLoader()
        let target = NSRect(x: -40, y: -180, width: 800, height: 800 * 792 / 612)
        let overlay = PageOverviewOverlayView(document: document, selectedIndex: 1, columns: 3,
                                              entryPageRect: target, thumbnailLoader: loader)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSView(frame: window.contentView!.bounds)
        window.contentView = host
        overlay.frame = host.bounds
        host.addSubview(overlay)
        window.orderFront(nil)
        defer { overlay.dismiss(animated: false); window.contentView = nil; window.close() }
        try await waitForTestCondition("Exit gallery thumbnails load") {
            loader.images.count == 3
        }
        let selected = try #require(overlay.layer?.sublayers?.first { $0.name == "page-1" })
        let neighbor = try #require(overlay.layer?.sublayers?.first { $0.name == "page-0" })
        let backdrop = try #require(overlay.layer?.sublayers?.first { $0.zPosition == -1 })
        let image = try #require(selected.sublayers?.first { $0.name == "thumbnail" })
        let scale = target.width / image.bounds.width

        overlay.dismiss(to: target)

        #expect(abs(selected.position.x - target.midX) < 0.001)
        let imageCenterY = selected.position.y + (image.frame.midY - selected.bounds.midY) * scale
        #expect(abs(imageCenterY - target.midY) < 0.001)
        #expect(abs(selected.transform.m11 - scale) < 0.001)
        #expect(selected.opacity == 1)
        #expect(neighbor.opacity == 0)
        #expect(backdrop.opacity == 1)
        let movement = try #require(selected.animation(forKey: "galleryTransition") as? CAAnimationGroup)
        #expect(movement.duration > 0)
        let fade = try #require(overlay.layer?.animation(forKey: "galleryExitFade") as? CAKeyframeAnimation)
        #expect(fade.keyPath == "opacity")
        let opacity = try #require(fade.values?.compactMap { ($0 as? NSNumber)?.doubleValue })
        let times = try #require(fade.keyTimes?.map(\.doubleValue))
        try #require(opacity.count == times.count)
        #expect(opacity.first == 1 && opacity.last == 0)
        #expect(times.first == 0 && times.last == 1)
        #expect(opacity.allSatisfy { (0...1).contains($0) })
        #expect(zip(opacity, opacity.dropFirst()).allSatisfy { $0.0 >= $0.1 })
        #expect(zip(times, times.dropFirst()).allSatisfy { $0.0 <= $0.1 })
        let firstFade = try #require(opacity.firstIndex { $0 < 1 })
        try #require(firstFade > 0)
        #expect(times[firstFade - 1] * fade.duration >= movement.duration - 0.001)
        #expect(fade.duration > movement.duration)
        let remainsMounted = overlay.superview === host
        #expect(remainsMounted)
        try await waitForTestCondition("Gallery exit removes the overlay") { overlay.superview == nil }
    }

    @Test
    func rapidReopenAndCancellationRemoveAnExitingGalleryImmediately() async throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        let page = PDFPage()
        page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        document.insert(page, at: 0)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let reader = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = reader
        reader.displayMode = .singlePageContinuous
        reader.document = document
        reader.autoScales = false
        reader.scaleFactor = 1
        reader.layoutDocumentView()
        reader.centerBothAxes(on: reader.pageCenterDestination(for: page))
        window.orderFront(nil)
        defer { reader.cancelPageOverview(); window.contentView = nil; window.close() }
        #expect(reader.beginPageOverview())
        let original = try #require(reader.pageOverviewController?.overlay)
        try await waitForTestCondition("Original gallery is presented") { original.alphaValue == 1 }
        reader.finishPageOverview()
        #expect(reader.beginPageOverview())
        let replacement = try #require(reader.pageOverviewController?.overlay)
        #expect(original.superview == nil)
        await nextTestMainQueueTurn()
        try await waitForTestCondition("Replacement gallery is presented") { replacement.alphaValue == 1 }
        let replacementRemainsMounted = replacement.superview === reader
        #expect(replacementRemainsMounted)

        reader.finishPageOverview()
        reader.cancelPageOverview()
        #expect(replacement.superview == nil)
        #expect(reader.subviews.compactMap { $0 as? PageOverviewOverlayView }.isEmpty)

        for resizes in [false, true] {
            #expect(reader.beginPageOverview())
            let exiting = try #require(reader.pageOverviewController?.overlay)
            try await waitForTestCondition("Gallery is presented before interruption") { exiting.alphaValue == 1 }
            reader.finishPageOverview()
            try await waitForTestCondition("Gallery exit starts before interruption") { exiting.dismissed }
            if resizes {
                exiting.setFrameSize(NSSize(width: exiting.frame.width - 100, height: exiting.frame.height))
            } else {
                reader.vimScroll(x: 0, y: 30)
                reader.stopScrollAnimation()
            }
            #expect(exiting.superview == nil)
        }
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
        try await waitForTestCondition("Gallery is ready for rapid navigation") { overlay.alphaValue == 1 }
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
        let buttons = overlay.subviews.compactMap { $0 as? NSButton }
        #expect(!buttons.isEmpty)
        #expect(buttons.allSatisfy { $0.bounds.width >= 30 && $0.bounds.height >= 30 })
        try await waitForTestCondition("Rapid navigation removes departing papers") {
            let papers = overlay.layer?.sublayers?.filter { $0.name?.hasPrefix("page-") == true } ?? []
            return Set(papers.compactMap(\.name)) == ["page-10", "page-11"]
                && papers.allSatisfy { $0.sublayers?.first { $0.name == "thumbnail" }?.contents != nil }
        }
    }
}
