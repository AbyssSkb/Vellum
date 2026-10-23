import AppKit
import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Selection endpoint overlay")
struct PDFSelectionEndpointOverlayTests {
    @Test
    func swappingEndpointsMovesTheMarkerWithoutChangingTheSelection() async throws {
        let (window, view) = try await makeReader()
        defer { close(window, view) }
        try selectBeta(in: view)
        let selection = try #require(view.currentSelection?.string)
        let first = try #require(view.selectionEndpointOverlay)
        let before = midpoint(first)

        #expect(view.vimSwapTextSelectionEndpoint())
        view.updateSelectionEndpointOverlay()

        #expect(view.currentSelection?.string == selection)
        let after = midpoint(first)
        #expect(abs(after.x - before.x) > 5)
        try expectMarkerOnNativeTextEdge(in: view, forward: false)
        #expect(view.vimSwapTextSelectionEndpoint())
        view.updateSelectionEndpointOverlay()
        #expect(abs(midpoint(first).x - before.x) < 0.01)
    }

    @Test(arguments: [0, 90, 180, 270])
    func markerFollowsTextRotationAndCroppedPageCoordinates(rotation: Int) async throws {
        let (window, view) = try await makeReader(rotation: rotation)
        defer { close(window, view) }
        try selectBeta(in: view)
        let overlay = try #require(view.selectionEndpointOverlay)
        #expect(!overlay.isHidden)
        try expectMarkerOnNativeTextEdge(in: view, forward: true)
        let horizontal = abs(overlay.caretEnd.x - overlay.caretStart.x)
        let vertical = abs(overlay.caretEnd.y - overlay.caretStart.y)
        if rotation == 90 || rotation == 270 {
            #expect(horizontal > 4)
            #expect(vertical < 0.01)
        } else {
            #expect(vertical > 4)
            #expect(horizontal < 0.01)
        }
        let selection = view.currentSelection?.string
        #expect(view.vimSwapTextSelectionEndpoint())
        view.updateSelectionEndpointOverlay()
        #expect(view.currentSelection?.string == selection)
        try expectMarkerOnNativeTextEdge(in: view, forward: false)
    }

    @Test(arguments: [90, 270])
    func explicitVisualSelectionSlotsKeepTheirOwnEndpoint(rotation: Int) async throws {
        let (window, view) = try await makeReader(rotation: rotation)
        defer { close(window, view) }
        let document = try #require(view.document)
        let page = try #require(document.page(at: 0))
        let pageStarts = view.textPageStarts(in: document)
        let lines = view.textLines(onPageAt: 0, pageStarts: pageStarts)
        let candidates = lines.compactMap { line -> (VimTextCaret, VimTextCaret, [Range<Int>])? in
            guard line.characters.count > 1,
                  let firstX = line.characters.first?.minX,
                  let anchor = view.targetCaret(in: line, preferredX: firstX) else { return nil }
            for endSlot in 2...line.characters.count {
                let ranges = TextSelectionRangeBuilder.pageRanges(for: line, startSlot: 0, endSlot: endSlot, pageStart: 0)
                guard ranges.count > 1 else { continue }
                let extent = VimTextCaret(
                    offset: view.offsetForSlot(endSlot, in: line), pageIndex: 0, slotIndex: endSlot,
                    point: view.pointForSlot(endSlot, in: line), lineMidY: line.midY
                )
                if let canonical = view.textCaret(
                    atInsertionOffset: extent.offset,
                    preferTrailingEdge: extent.offset >= anchor.offset,
                    pageStarts: pageStarts
                ), view.sameVisualCaret(extent, canonical),
                   abs(extent.point.x - canonical.point.x) < 0.01,
                   abs(extent.point.y - canonical.point.y) < 0.01 { continue }
                return (anchor, extent, ranges)
            }
            return nil
        }
        let (anchor, extent, ranges) = try #require(candidates.first)
        #expect(ranges.count > 1)
        let applied = view.applyVisualTextSelection(anchorCaret: anchor, extentCaret: extent, pageStarts: pageStarts)
        try #require(applied)
        #expect(view.currentSelection?.numberOfTextRanges(on: page) ?? 0 > 1)
        view.textSelectionNavigationState = VimTextSelectionNavigationState(
            anchorOffset: anchor.offset, extentOffset: extent.offset, preferredX: nil,
            anchorCaret: anchor, extentCaret: extent
        )
        view.updateSelectionEndpointOverlay()
        try expectMarkerAtCaret(in: view)
    }

    @Test
    func zoomResizeAndScrollMoveTheMarkerWithThePaper() async throws {
        let (window, view) = try await makeReader()
        defer { close(window, view) }
        try selectBeta(in: view)
        let overlay = try #require(view.selectionEndpointOverlay)
        let initialHeight = abs(overlay.caretEnd.y - overlay.caretStart.y)
        view.scaleFactor *= 2
        view.layoutDocumentView()
        view.scrollToDocumentEdge(.top)
        view.updateSelectionEndpointOverlay()
        #expect(abs(overlay.caretEnd.y - overlay.caretStart.y) > initialHeight * 1.8)
        try expectMarkerOnNativeTextEdge(in: view, forward: true)

        view.frame.size.width -= 120
        view.layoutDocumentView()
        view.updateSelectionEndpointOverlay()
        #expect(overlay.frame == view.wordJumpViewport)
        try expectMarkerOnNativeTextEdge(in: view, forward: true)

        let scrollView = try #require(view.pdfScrollView)
        let clip = scrollView.contentView
        let before = view.convert(midpoint(overlay), from: overlay)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: clip.bounds.origin.y + 20))
        scrollView.reflectScrolledClipView(clip)
        view.updateSelectionEndpointOverlay()
        let after = view.convert(midpoint(overlay), from: overlay)
        #expect(abs(after.y - before.y) > 15)
        try expectMarkerOnNativeTextEdge(in: view, forward: true)

        view.scaleFactor = 2
        view.layoutDocumentView()
        view.scrollToDocumentEdge(.bottom)
        view.updateSelectionEndpointOverlay()
        #expect(overlay.isHidden)
    }

    @Test
    func markerDoesNotInterceptPointerInputAndHidesDuringOtherInteractions() async throws {
        let (window, view) = try await makeReader()
        defer { close(window, view) }
        try selectBeta(in: view)
        let overlay = try #require(view.selectionEndpointOverlay)
        #expect(overlay.hitTest(midpoint(overlay)) == nil)
        #expect(view.hitTest(view.convert(midpoint(overlay), from: overlay)) !== overlay)

        view.isMouseSelectingText = true
        view.updateSelectionEndpointOverlay()
        #expect(overlay.isHidden)
        view.isMouseSelectingText = false
        view.updateSelectionEndpointOverlay()
        #expect(!overlay.isHidden)

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        view.addSubview(field)
        #expect(window.makeFirstResponder(field))
        view.updateSelectionEndpointOverlay()
        #expect(overlay.isHidden)
        #expect(window.makeFirstResponder(view))
        field.removeFromSuperview()
        view.updateSelectionEndpointOverlay()
        #expect(!overlay.isHidden)

        let aiOverlay = NSView(frame: .zero)
        view.addSubview(aiOverlay)
        view.aiInteraction.explanationOverlay = aiOverlay
        view.updateSelectionEndpointOverlay()
        #expect(overlay.isHidden)
        view.aiInteraction.clearPopoverState()

        #expect(view.beginPageOverview())
        view.updateSelectionEndpointOverlay()
        #expect(overlay.isHidden)
        view.cancelPageOverview()
        view.beginWordJumpCommand()
        #expect(view.isWordJumpActive)
        view.updateSelectionEndpointOverlay()
        #expect(overlay.isHidden)
        view.cancelWordJump()
        view.updateSelectionEndpointOverlay()
        #expect(!overlay.isHidden)
    }

    @Test
    func clearingTheSelectionSearchingAndReplacingTheDocumentHideTheMarker() async throws {
        let (window, view) = try await makeReader()
        defer { close(window, view) }
        try selectBeta(in: view)
        let overlay = try #require(view.selectionEndpointOverlay)
        view.clearTextSelectionForVimNavigation()
        view.updateSelectionEndpointOverlay()
        #expect(overlay.isHidden)

        try selectBeta(in: view)
        view.vimSearchSelectedText()
        view.updateSelectionEndpointOverlay()
        #expect(view.currentSelection == nil)
        #expect(overlay.isHidden)
        view.searchController?.clear()

        try selectBeta(in: view)
        view.document = try makeTextPDF(pages: [[("replacement", NSPoint(x: 72, y: 650))]])
        view.updateSelectionEndpointOverlay()
        #expect(overlay.isHidden)
    }

    private func makeReader(rotation: Int = 0) async throws -> (NSWindow, VellumPDFView) {
        _ = NSApplication.shared
        let document = try makeTextPDF(pages: [[
            ("alpha beta gamma delta", NSPoint(x: 72, y: 650)),
            ("one two three four five", NSPoint(x: 72, y: 620)),
            ("quick brown fox jumps", NSPoint(x: 72, y: 590))
        ]])
        let page = try #require(document.page(at: 0))
        page.rotation = rotation
        page.setBounds(NSRect(x: 40, y: 40, width: 540, height: 720), for: .cropBox)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = VellumPDFView(frame: try #require(window.contentView).bounds)
        window.contentView = view
        view.displayMode = .singlePageContinuous
        view.displayBox = .cropBox
        view.document = document
        view.autoScales = false
        view.scaleFactor = 0.65
        view.layoutSubtreeIfNeeded()
        view.pdfScrollView?.layoutSubtreeIfNeeded()
        view.layoutDocumentView()
        view.scrollToDocumentEdge(.top)
        #expect(window.makeFirstResponder(view))
        await nextTestMainQueueTurn()
        return (window, view)
    }

    private func selectBeta(in view: VellumPDFView) throws {
        let document = try #require(view.document)
        let page = try #require(document.page(at: 0))
        let text = try #require(page.string as NSString?)
        let range = text.range(of: "beta")
        try #require(range.location != NSNotFound)
        view.textSelectionNavigationState = nil
        view.setCurrentSelection(page.selection(for: range), animate: false)
        _ = view.textSelectionState(pageStarts: view.textPageStarts(in: document))
        view.updateSelectionEndpointOverlay()
    }

    private func expectMarkerAtCaret(in view: VellumPDFView) throws {
        let overlay = try #require(view.selectionEndpointOverlay)
        let caret = try #require(view.textSelectionNavigationState?.extentCaret)
        let page = try #require(view.document?.page(at: caret.pageIndex))
        let geometry = PDFPageDisplayGeometry(page: page, box: view.displayBox)
        let expected = overlay.convert(view.convert(geometry.pagePoint(forDisplayPoint: caret.point), from: page), from: view)
        #expect(!overlay.isHidden)
        #expect(abs(midpoint(overlay).x - expected.x) < 0.01)
        #expect(abs(midpoint(overlay).y - expected.y) < 0.01)
    }

    private func expectMarkerOnNativeTextEdge(in view: VellumPDFView, forward: Bool) throws {
        let overlay = try #require(view.selectionEndpointOverlay)
        let page = try #require(view.document?.page(at: 0))
        let selection = try #require(view.currentSelection)
        let range = selection.range(at: 0, on: page)
        let offset = forward ? NSMaxRange(range) - 1 : range.location
        let character = try #require(page.selection(for: NSRange(location: offset, length: 1))).bounds(for: page)
        let x = forward ? character.maxX : character.minX
        let start = overlay.convert(view.convert(NSPoint(x: x, y: character.minY), from: page), from: view)
        let end = overlay.convert(view.convert(NSPoint(x: x, y: character.maxY), from: page), from: view)
        #expect(!overlay.isHidden)
        #expect(abs(midpoint(overlay).x - (start.x + end.x) / 2) < 0.01)
        #expect(abs(midpoint(overlay).y - (start.y + end.y) / 2) < 0.01)
        #expect(abs(abs(overlay.caretEnd.x - overlay.caretStart.x) - abs(end.x - start.x)) < 0.01)
        #expect(abs(abs(overlay.caretEnd.y - overlay.caretStart.y) - abs(end.y - start.y)) < 0.01)
    }

    private func midpoint(_ overlay: SelectionEndpointOverlay) -> NSPoint {
        NSPoint(x: (overlay.caretStart.x + overlay.caretEnd.x) / 2,
                y: (overlay.caretStart.y + overlay.caretEnd.y) / 2)
    }

    private func close(_ window: NSWindow, _ view: VellumPDFView) {
        view.searchController?.clear()
        view.cancelPageOverview()
        view.cancelWordJump()
        view.cancelPendingRestore()
        view.stopScrollAnimation()
        view.stopZoomState()
        window.contentView = nil
        window.close()
    }
}
