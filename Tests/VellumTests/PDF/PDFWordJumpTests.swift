@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@Suite("PDF word jump")
struct PDFWordJumpTests {
    @Test @MainActor
    func onlyWordsIntersectingTheViewportReceiveTargets() async throws {
        let (window, view) = try await makeReader(pages: [
            [("visible", NSPoint(x: 72, y: 650)), ("below", NSPoint(x: 72, y: 100))],
            [("nextpage", NSPoint(x: 72, y: 650))]
        ])
        defer { window.close() }
        view.beginWordJumpCommand()
        let controller = try #require(view.wordJumpController)
        #expect(controller.targets.map(\.word) == ["visible"])
        #expect(controller.targets.allSatisfy { $0.rects.allSatisfy { $0.intersects(view.visibleRect) } })
    }

    @Test @MainActor
    func unclippedAncestorsDoNotIncludeWordsOutsideTheReadingViewport() async throws {
        let (window, view) = try await makeReader(pages: [[
            ("outside", NSPoint(x: 72, y: 650)),
            ("visible", NSPoint(x: 72, y: 600))
        ]])
        defer { window.close() }
        let page = try #require(view.document?.page(at: 0))
        let outsideRange = (try #require(page.string) as NSString).range(of: "outside")
        let outsideBounds = try #require(page.selection(for: outsideRange)).bounds(for: page)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        container.clipsToBounds = false
        view.removeFromSuperview()
        window.setContentSize(container.frame.size)
        window.contentView = container
        view.frame = container.bounds.insetBy(dx: 100, dy: 100)
        view.clipsToBounds = false
        container.addSubview(view)
        view.scaleFactor = 2
        view.layoutDocumentView()
        view.centerBothAxes(on: PDFDestination(page: page,
            at: NSPoint(x: outsideBounds.midX, y: outsideBounds.midY - 130)))
        await nextTestMainQueueTurn()
        let clipView = try #require(view.pdfScrollView?.contentView)
        try await waitForTestCondition("The centered page is visible in the reading viewport") {
            view.visiblePages.contains { $0 === page }
                && !view.convert(outsideBounds, from: page)
                    .intersects(view.bounds.intersection(view.convert(clipView.bounds, from: clipView)))
        }
        let readingArea = view.bounds.intersection(view.convert(clipView.bounds, from: clipView))
        #expect(!view.bounds.contains(view.visibleRect))
        #expect(view.wordJumpViewport == readingArea.intersection(view.visibleRect))
        let outsideRect = try #require(view.viewRect(for: outsideBounds, on: page))
        #expect(view.visibleRect.contains(outsideRect))
        #expect(!outsideRect.intersects(readingArea))

        view.beginWordJumpCommand()
        let controller = try #require(view.wordJumpController)
        #expect(controller.targets.contains { $0.word == "visible" })
        #expect(!controller.targets.contains { $0.word == "outside" })
        #expect(controller.targets.allSatisfy { $0.rects.allSatisfy { $0.intersects(readingArea) } })
    }

    @Test @MainActor
    func choosingARepeatedWordSelectsItsActualRangeAndSupportsVisualMotions() async throws {
        let (window, view) = try await makeReader(pages: [[
            ("alpha beta", NSPoint(x: 72, y: 650)),
            ("alpha gamma delta", NSPoint(x: 72, y: 610))
        ]])
        defer { window.close() }
        let page = try #require(view.document?.page(at: 0))
        view.beginWordJumpCommand()
        let controller = try #require(view.wordJumpController)
        for character in "alp" { try send(String(character), to: view) }
        #expect(controller.session.matches.count == 2)
        let match = try #require(controller.session.matches.last)
        let expected = (try #require(page.string) as NSString).range(of: "alpha", options: .backwards)
        try #require(expected.location != NSNotFound)
        for character in match.label { try send(String(character), to: view) }
        #expect(!view.isWordJumpActive)
        #expect(view.currentSelection?.range(at: 0, on: page) == expected)
        #expect(window.firstResponder === view)
        #expect(view.handleTextSelectionKey("e", eventType: .keyDown))
        #expect(view.currentSelection?.string == "alpha gamma")
        #expect(view.handleTextSelectionKey("w", eventType: .keyDown))
        #expect(view.currentSelection?.string?.hasPrefix("alpha gamma") == true)
        #expect((view.currentSelection?.range(at: 0, on: page).length ?? 0) > expected.length)
    }

    @Test @MainActor
    func cancellingEditingAndUnmatchedEnterPreserveTheExistingSelection() async throws {
        let (window, view) = try await makeReader(pages: [[("alpha beta", NSPoint(x: 72, y: 650))]])
        defer { window.close() }
        let page = try #require(view.document?.page(at: 0))
        let originalRange = (try #require(page.string) as NSString).range(of: "beta")
        view.setCurrentSelection(page.selection(for: originalRange), animate: false)
        view.beginWordJumpCommand()
        try send("\r", to: view)
        #expect(view.isWordJumpActive)
        #expect(view.currentSelection?.range(at: 0, on: page) == originalRange)
        try send("a", to: view)
        try send("\u{7f}", to: view)
        #expect(view.currentSelection?.range(at: 0, on: page) == originalRange)
        for character in "unmatched" { try send(String(character), to: view) }
        try send("\r", to: view)
        #expect(view.isWordJumpActive)
        #expect(view.currentSelection?.range(at: 0, on: page) == originalRange)
        try send("\u{1b}", to: view)
        #expect(!view.isWordJumpActive)
        #expect(view.currentSelection?.range(at: 0, on: page) == originalRange)
    }

    @Test @MainActor
    func hyphenatedLinesCreateOneCompleteWordTarget() async throws {
        let (window, view) = try await makeReader(pages: [[
            ("broken-", NSPoint(x: 72, y: 650)),
            ("word after", NSPoint(x: 72, y: 625))
        ]])
        defer { window.close() }
        let page = try #require(view.document?.page(at: 0))
        view.beginWordJumpCommand()
        let controller = try #require(view.wordJumpController)
        #expect(controller.targets.filter { $0.word == "brokenword" }.count == 1)
        #expect(!controller.targets.contains { $0.word == "broken" || $0.word == "word" })
        for character in "brokenw" { try send(String(character), to: view) }
        let match = try #require(controller.session.matches.first)
        #expect(controller.targets[match.wordIndex].rects.count == 2)
        for character in match.label { try send(String(character), to: view) }
        let expectedRange = (try #require(page.string) as NSString).range(of: "broken-\nword")
        try #require(expectedRange.location != NSNotFound)
        #expect(view.currentSelection?.range(at: 0, on: page) == expectedRange)
    }

    @Test @MainActor
    func partiallyVisibleHyphenatedWordIsIncludedWhenBothRangeEndpointsAreOffscreen() async throws {
        let (window, view) = try await makeReader(pages: [[
            ("The paragraph ends with broken-", NSPoint(x: 72, y: 650)),
            ("word after", NSPoint(x: 72, y: 625))
        ]])
        defer { window.close() }
        let page = try #require(view.document?.page(at: 0))
        let text = try #require(page.string) as NSString
        let prefixRange = text.range(of: "broken")
        let suffixRange = text.range(of: "word")
        try #require(prefixRange.location != NSNotFound && suffixRange.location != NSNotFound)
        let fullRange = NSRange(location: prefixRange.location, length: NSMaxRange(suffixRange) - prefixRange.location)
        window.setContentSize(NSSize(width: 200, height: 420))
        view.scaleFactor = 5
        view.layoutDocumentView()
        let visibleCharacter = page.characterBounds(at: suffixRange.location)
        view.centerBothAxes(on: PDFDestination(page: page,
            at: NSPoint(x: visibleCharacter.midX, y: visibleCharacter.midY)))
        await nextTestMainQueueTurn()
        try await waitForTestCondition("The middle fragment is visible after centering") {
            view.visiblePages.contains { $0 === page }
                && view.convert(visibleCharacter, from: page).intersects(view.visibleRect)
        }
        #expect(view.convert(visibleCharacter, from: page).intersects(view.visibleRect))
        #expect(!view.convert(page.characterBounds(at: fullRange.location), from: page).intersects(view.visibleRect))
        #expect(!view.convert(page.characterBounds(at: NSMaxRange(fullRange) - 1), from: page).intersects(view.visibleRect))
        let endpointBounds = page.characterBounds(at: fullRange.location)
            .union(page.characterBounds(at: NSMaxRange(fullRange) - 1))
        #expect(!view.convert(endpointBounds, from: page).intersects(view.visibleRect))

        view.beginWordJumpCommand()
        let controller = try #require(view.wordJumpController)
        let target = try #require(controller.targets.first { $0.word == "brokenword" })
        #expect(controller.targets.filter { $0.word == "brokenword" }.count == 1)
        #expect(target.rects.count == 1)
        #expect(target.rects[0].intersects(view.visibleRect))
    }

    @Test(arguments: [0, 90, 180, 270]) @MainActor
    func rotatedCroppedTargetsUseTheDisplayedPageGeometry(rotation: Int) async throws {
        let (window, view) = try await makeReader(pages: [[
            ("alpha", NSPoint(x: 100, y: 650)),
            ("beta", NSPoint(x: 100, y: 200))
        ]])
        defer { window.close() }
        let page = try #require(view.document?.page(at: 0))
        page.setBounds(NSRect(x: 20, y: 30, width: 500, height: 700), for: .cropBox)
        page.rotation = rotation
        view.displayBox = .cropBox
        view.scaleFactor = 0.45
        view.layoutDocumentView()
        view.scrollToDocumentEdge(.top)
        view.beginWordJumpCommand()
        let targets = try #require(view.wordJumpController).targets
        #expect(Set(targets.map(\.word)) == ["alpha", "beta"])
        for target in targets {
            let bounds = target.selection.bounds(for: page)
            let firstCorner = view.convert(NSPoint(x: bounds.minX, y: bounds.minY), from: page)
            let oppositeCorner = view.convert(NSPoint(x: bounds.maxX, y: bounds.maxY), from: page)
            let expected = NSRect(
                x: min(firstCorner.x, oppositeCorner.x),
                y: min(firstCorner.y, oppositeCorner.y),
                width: abs(firstCorner.x - oppositeCorner.x),
                height: abs(firstCorner.y - oppositeCorner.y)
            )
            let actual = try #require(target.rects.first)
            #expect(abs(actual.minX - expected.minX) < 0.000001)
            #expect(abs(actual.minY - expected.minY) < 0.000001)
            #expect(abs(actual.width - expected.width) < 0.000001)
            #expect(abs(actual.height - expected.height) < 0.000001)
            let displayedSize = rotation % 180 == 0 ? bounds.size : NSSize(width: bounds.height, height: bounds.width)
            #expect(abs(actual.width - displayedSize.width * view.scaleFactor) < 0.001)
            #expect(abs(actual.height - displayedSize.height * view.scaleFactor) < 0.001)
            #expect(actual.intersects(view.visibleRect))
        }
    }

    @Test(arguments: ["scroll", "resize", "document"]) @MainActor
    func changingTheViewportOrDocumentCancelsStaleLabels(change: String) async throws {
        let (window, view) = try await makeReader(pages: [
            [("alpha", NSPoint(x: 72, y: 650))],
            [("beta", NSPoint(x: 72, y: 650))]
        ])
        defer { window.close() }
        view.beginWordJumpCommand()
        try send("a", to: view)
        let controller = try #require(view.wordJumpController)
        let label = try #require(controller.session.matches.first).label
        switch change {
        case "scroll": view.scrollToDocumentEdge(.bottom)
        case "resize": view.setFrameSize(NSSize(width: 700, height: 500))
        default: view.document = PDFDocument()
        }
        _ = view.handleWordJumpKey(try event(label, in: window))
        #expect(!view.isWordJumpActive)
        #expect(controller.targets.isEmpty)
        #expect(view.currentSelection == nil)
    }

    @Test @MainActor
    func pagesWithoutTextRemainCancellable() async throws {
        let (window, view) = try await makeReader(pages: [[]])
        defer { window.close() }
        view.beginWordJumpCommand()
        #expect(view.isWordJumpActive)
        #expect(view.wordJumpController?.targets.isEmpty == true)
        try send("a", to: view)
        try send("\r", to: view)
        #expect(view.currentSelection == nil)
        try send("\u{1b}", to: view)
        #expect(!view.isWordJumpActive)
    }

    @Test @MainActor
    func hoveringAnAIHighlightDoesNotInterruptWordJump() async throws {
        let (window, view) = try await makeReader(pages: [[("alpha", NSPoint(x: 72, y: 650))]])
        defer { view.hideAIExplanationPopover(); window.close() }
        let page = try #require(view.document?.page(at: 0))
        let range = (try #require(page.string) as NSString).range(of: "alpha")
        let bounds = try #require(page.selection(for: range)).bounds(for: page)
        let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
        annotation.contents = AIExplanationAnnotation.encode("Saved explanation")
        page.addAnnotation(annotation)
        let point = view.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: page)
        #expect(view.aiExplanationAnnotation(at: point) === annotation)
        let mouse = try #require(NSEvent.mouseEvent(with: .mouseMoved,
            location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0))
        view.beginWordJumpCommand()
        view.updateHoveredAIExplanation(for: mouse)
        #expect(view.isWordJumpActive)
        #expect(!view.aiInteraction.isActive)
        #expect(view.aiInteraction.hoveredAnnotation == nil)
        #expect(window.firstResponder === view)
    }

    @MainActor
    private func makeReader(pages: [[(String, NSPoint)]]) async throws -> (NSWindow, VellumPDFView) {
        _ = NSApplication.shared
        let document = try makeTextPDF(pages: pages)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 420),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: try #require(window.contentView).bounds)
        window.contentView = view
        view.displayMode = .singlePageContinuous
        view.document = document
        view.autoScales = false
        view.scaleFactor = 1
        view.layoutSubtreeIfNeeded()
        view.pdfScrollView?.layoutSubtreeIfNeeded()
        view.layoutDocumentView()
        view.goToFirstPage(nil)
        view.scrollToDocumentEdge(.top)
        await nextTestMainQueueTurn()
        let firstPage = try #require(document.page(at: 0))
        do {
            try await waitForTestCondition("The first PDF page is visible after layout") {
                view.currentPage === firstPage && view.visiblePages.contains { $0 === firstPage }
            }
        } catch {
            window.close()
            throw error
        }
        return (window, view)
    }

    @MainActor
    private func event(_ key: String, in window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0))
    }

    @MainActor
    private func send(_ key: String, to view: VellumPDFView) throws {
        #expect(view.handleWordJumpKey(try event(key, in: #require(view.window))))
    }
}
