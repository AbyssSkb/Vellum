@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@Suite("PDF word jump")
struct PDFWordJumpTests {
    @Test @MainActor
    func entryHintUsesAToastUntilTheFirstMatchingLetter() async throws {
        let (window, view) = try await makeReader(pages: [[("alpha beta", NSPoint(x: 72, y: 650))]])
        defer { view.cancelWordJump(); window.close() }
        view.beginWordJumpCommand()
        let hint = try #require(window.contentView?.superview?.subviews.compactMap { $0 as? ToastView }.first)
        #expect(hint.message == AppUILanguage.saved().text(.wordJumpTypeHint))
        #expect(hint.kind == .info)
        #expect(!hint.autoDismiss)
        try send("\r", to: view)
        try send("\u{7f}", to: view)
        #expect(hint.superview != nil)
        try send("a", to: view)
        #expect(view.isWordJumpActive)
        #expect(view.wordJumpController?.session.matches.count == 1)
        #expect(hint.superview == nil)
    }

    @Test @MainActor
    func linkHintsIncludeVisibleActionsWithoutRequiringATextLayer() async throws {
        let (window, view) = try await makeReader(pages: [[], []])
        defer { window.close() }
        let page = try #require(view.document?.page(at: 0))
        let nextPage = try #require(view.document?.page(at: 1))
        let visible = PDFAnnotation(bounds: NSRect(x: 72, y: 650, width: 80, height: 18), forType: .link, withProperties: nil)
        visible.url = URL(string: "https://example.com/reference")
        page.addAnnotation(visible)
        let hidden = PDFAnnotation(bounds: NSRect(x: 72, y: 610, width: 80, height: 18), forType: .link, withProperties: nil)
        hidden.url = visible.url
        hidden.shouldDisplay = false
        page.addAnnotation(hidden)
        let below = PDFAnnotation(bounds: NSRect(x: 72, y: 100, width: 80, height: 18), forType: .link, withProperties: nil)
        below.url = visible.url
        page.addAnnotation(below)
        let empty = PDFAnnotation(bounds: NSRect(x: 72, y: 570, width: 80, height: 18), forType: .link, withProperties: nil)
        page.addAnnotation(empty)
        let otherPage = PDFAnnotation(bounds: visible.bounds, forType: .link, withProperties: nil)
        otherPage.url = visible.url
        nextPage.addAnnotation(otherPage)

        view.beginLinkJumpCommand()
        let controller = try #require(view.wordJumpController)
        #expect(controller.targets.count == 1)
        #expect(controller.targets.first?.link === visible)
        #expect(controller.session.matches.count == 1)
        #expect(controller.session.query.isEmpty)
        try send("\u{1b}", to: view)
        #expect(!view.isWordJumpActive)
    }

    @Test(arguments: [false, true]) @MainActor
    func linkHintSizeTracksReaderSizeOnlyForPreview(preview: Bool) async throws {
        let (window, view) = try await makeReader(pages: [[], []])
        defer { view.cancelWordJump(); window.close() }
        let page = try #require(view.document?.page(at: 0))
        let link = PDFAnnotation(bounds: NSRect(x: 72, y: 650, width: 80, height: 18), forType: .link, withProperties: nil)
        link.destination = PDFDestination(page: try #require(view.document?.page(at: 1)), at: .zero)
        page.addAnnotation(link)

        func labelSize(windowSize: NSSize) throws -> NSSize {
            view.cancelWordJump()
            window.setContentSize(windowSize)
            view.autoScales = false
            view.scaleFactor = 1
            view.layoutSubtreeIfNeeded()
            view.layoutDocumentView()
            view.scrollToDocumentEdge(.top)
            if preview { view.beginLinkPreviewCommand() } else { view.beginLinkJumpCommand() }
            let overlay = try #require(view.subviews.first { String(describing: type(of: $0)).contains("WordJumpOverlayView") })
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(overlay.bounds.width), pixelsHigh: Int(overlay.bounds.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.clear(overlay.bounds)
            overlay.draw(overlay.bounds)
            NSGraphicsContext.restoreGraphicsState()
            var minX = bitmap.pixelsWide, maxX = -1, minY = bitmap.pixelsHigh, maxY = -1
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                          color.alphaComponent > 0.9, color.redComponent > 0.4, color.redComponent < 0.6,
                          color.greenComponent > 0.7, color.blueComponent > 0.9 else { continue }
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            try #require(maxX >= minX && maxY >= minY)
            return NSSize(width: maxX - minX + 1, height: maxY - minY + 1)
        }

        let small = try labelSize(windowSize: NSSize(width: 600, height: 420))
        let large = try labelSize(windowSize: NSSize(width: 1200, height: 800))
        if preview {
            #expect(large.width > small.width)
            #expect(large.height > small.height)
        } else {
            #expect(abs(large.width - small.width) <= 1)
            #expect(abs(large.height - small.height) <= 1)
        }
    }

    @Test @MainActor
    func referencePreviewAcceptsMultiCharacterLabels() async throws {
        let (window, view) = try await makeReader(pages: [[], []])
        defer { view.cancelWordJump(); view.cancelLinkPreview(); window.close() }
        let page = try #require(view.document?.page(at: 0))
        let destination = PDFDestination(page: try #require(view.document?.page(at: 1)), at: .zero)
        for index in 0..<27 {
            let link = PDFAnnotation(bounds: NSRect(x: 40 + (index % 9) * 50, y: 690 - (index / 9) * 40,
                                                    width: 30, height: 15), forType: .link, withProperties: nil)
            link.destination = destination
            page.addAnnotation(link)
        }
        view.beginLinkPreviewCommand()
        let controller = try #require(view.wordJumpController)
        #expect(controller.targets.count == 27)
        let label = try #require(controller.session.matches.first).label
        #expect(label.count == 2)
        try send(String(try #require(label.first)), to: view)
        #expect(view.isWordJumpActive)
        try send(String(try #require(label.last)), to: view)
        #expect(!view.isWordJumpActive)
        #expect(view.referenceController?.preview != nil)
    }

    @Test(arguments: [0, 90, 180, 270]) @MainActor
    func linkHintsRespectPageCropAndRotation(rotation: Int) async throws {
        let (window, view) = try await makeReader(pages: [[]])
        defer { window.close() }
        let page = try #require(view.document?.page(at: 0))
        page.setBounds(NSRect(x: 100, y: 100, width: 400, height: 600), for: .cropBox)
        page.rotation = rotation
        view.displayBox = .cropBox
        view.scaleFactor = 0.45
        view.layoutDocumentView()
        view.scrollToDocumentEdge(.top)
        let visible = PDFAnnotation(bounds: NSRect(x: 80, y: 650, width: 80, height: 18), forType: .link, withProperties: nil)
        visible.url = URL(string: "https://example.com/reference")
        page.addAnnotation(visible)
        let outside = PDFAnnotation(bounds: NSRect(x: 20, y: 650, width: 60, height: 18), forType: .link, withProperties: nil)
        outside.url = visible.url
        page.addAnnotation(outside)

        view.beginLinkJumpCommand()
        let targets = try #require(view.wordJumpController).targets
        #expect(targets.count == 1)
        let target = try #require(targets.first)
        #expect(target.link === visible)
        let cropped = visible.bounds.intersection(page.bounds(for: .cropBox))
        let expected = try #require(view.viewRect(for: cropped, on: page)).intersection(view.wordJumpViewport)
        #expect(target.rects == [expected])
        #expect(target.rotation == rotation)
    }

    @Test(arguments: [false, true]) @MainActor
    func choosingAnInternalLinkRecordsAndRestoresTheReadingPosition(useAction: Bool) async throws {
        let (window, view) = try await makeReader(pages: [[("source", NSPoint(x: 72, y: 650))], [], []])
        defer { window.close() }
        let page = try #require(view.document?.page(at: 0))
        let destinationPage = try #require(view.document?.page(at: 2))
        let destination = PDFDestination(page: destinationPage, at: NSPoint(x: 72, y: 650))
        let link = PDFAnnotation(bounds: NSRect(x: 72, y: 650, width: 80, height: 18), forType: .link, withProperties: nil)
        if useAction {
            link.action = PDFActionGoTo(destination: destination)
        } else {
            link.destination = destination
        }
        page.addAnnotation(link)
        view.setCurrentSelection(page.selection(for: NSRange(location: 0, length: 6)), animate: false)
        try #require(view.hasNavigableTextSelection)
        view.beginLinkJumpCommand()
        let before = try #require(view.snapshot())
        let match = try #require(view.wordJumpController?.session.matches.first)
        for character in match.label { try send(String(character), to: view) }
        #expect(!view.isWordJumpActive)
        #expect(!view.hasNavigableTextSelection)
        #expect(view.jumpBackStack == [before])
        await nextTestMainQueueTurn()
        await nextTestMainQueueTurn()
        try await waitForTestCondition("The chosen internal link reaches its destination") {
            view.currentPage === destinationPage
        }
        view.vimJumpBack()
        try await waitForTestCondition("Jump back restores the link source") {
            guard let restored = view.snapshot() else { return false }
            return restored.pageIndex == before.pageIndex && view.isSameJumpLocation(restored, before)
        }
    }

    @Test(arguments: ["scroll", "zoom", "document"]) @MainActor
    func linkHintsCancelWhenTheirTargetsBecomeStale(change: String) async throws {
        let (window, view) = try await makeReader(pages: [[], []])
        defer { window.close() }
        let page = try #require(view.document?.page(at: 0))
        let link = PDFAnnotation(bounds: NSRect(x: 72, y: 650, width: 80, height: 18), forType: .link, withProperties: nil)
        link.destination = PDFDestination(page: try #require(view.document?.page(at: 1)), at: .zero)
        page.addAnnotation(link)
        view.beginLinkJumpCommand()
        let label = try #require(view.wordJumpController?.session.matches.first).label
        switch change {
        case "scroll": view.scrollToDocumentEdge(.bottom)
        case "zoom": view.scaleFactor *= 1.5
        default: view.document = PDFDocument()
        }
        _ = view.handleWordJumpKey(try event(label, in: window))
        #expect(!view.isWordJumpActive)
        #expect(view.jumpBackStack.isEmpty)
    }

    @Test @MainActor
    func pagesWithoutLinksDoNotCaptureKeysAndPreserveTheSelection() async throws {
        let (window, view) = try await makeReader(pages: [[("alpha", NSPoint(x: 72, y: 650))]])
        defer { window.close() }
        let page = try #require(view.document?.page(at: 0))
        let selection = try #require(page.selection(for: NSRange(location: 0, length: 5)))
        view.setCurrentSelection(selection, animate: false)
        view.beginLinkJumpCommand()
        #expect(!view.isWordJumpActive)
        #expect(view.wordJumpController?.targets.isEmpty == true)
        #expect(!view.handleWordJumpKey(try event("j", in: window)))
        #expect(view.currentSelection?.string == "alpha")
    }

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

    @Test(arguments: [1, 2]) @MainActor
    func labelAreaCoversTheExactOriginalCharactersAtDifferentWidths(characterCount: Int) async throws {
        let (window, view) = try await makeReader(pages: [[("ill WWW", NSPoint(x: 72, y: 650))]])
        defer { view.cancelWordJump(); window.close() }
        let page = try #require(view.document?.page(at: 0))
        let text = try #require(page.string) as NSString
        view.beginWordJumpCommand()
        let targets = try #require(view.wordJumpController).targets
        var areas: [NSRect] = []
        for word in ["ill", "WWW"] {
            let target = try #require(targets.first { $0.word == word })
            let range = NSRange(location: text.range(of: word).location, length: characterCount)
            let prefixSelection = try #require(page.selection(for: range))
            let expected = try #require(view.viewRect(for: prefixSelection.bounds(for: page), on: page))
            let area = try #require(target.labelArea(characterCount: characterCount, in: view))
            #expect(area.characterCount == characterCount)
            expectSameRect(area.rect, expected)
            areas.append(area.rect)
        }
        #expect(areas[1].width > areas[0].width * 2)
    }

    @Test @MainActor
    func labelAreaStopsAtTheEndOfAShortWordAndDoesNotIncludeTheNextWord() async throws {
        let (window, view) = try await makeReader(pages: [[("a broader", NSPoint(x: 72, y: 650))]])
        defer { view.cancelWordJump(); window.close() }
        let page = try #require(view.document?.page(at: 0))
        let text = try #require(page.string) as NSString
        view.beginWordJumpCommand()
        let target = try #require(view.wordJumpController?.targets.first { $0.word == "a" })
        let original = try #require(page.selection(for: text.range(of: "a")))
        let expected = try #require(view.viewRect(for: original.bounds(for: page), on: page))
        for count in [2, 99] {
            let area = try #require(target.labelArea(characterCount: count, in: view))
            #expect(area.characterCount == 1)
            expectSameRect(area.rect, expected)
        }
        #expect(target.labelArea(characterCount: 0, in: view) == nil)
        let link = PDFWordJumpTarget(selection: nil, word: "a", rects: [expected], link: nil)
        #expect(link.labelArea(characterCount: 2, in: view) == nil)
    }

    @Test @MainActor
    func labelAreaDoesNotBridgeDifferentSelectedRangesOnTheSameLine() async throws {
        let (window, view) = try await makeReader(pages: [[("alpha beta", NSPoint(x: 72, y: 650))]])
        defer { window.close() }
        let document = try #require(view.document)
        let page = try #require(document.page(at: 0))
        let text = try #require(page.string) as NSString
        let firstRange = NSRange(location: text.range(of: "alpha").location, length: 1)
        let first = try #require(page.selection(for: firstRange))
        let selection = PDFSelection(document: document)
        selection.add(first)
        selection.add(try #require(page.selection(for: text.range(of: "beta"))))
        #expect(selection.numberOfTextRanges(on: page) == 2)
        let target = PDFWordJumpTarget(selection: selection, word: "abeta", rects: [], link: nil)
        let area = try #require(target.labelArea(characterCount: 2, in: view))
        #expect(area.characterCount == 1)
        expectSameRect(area.rect, try #require(view.viewRect(for: first.bounds(for: page), on: page)))
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
    func cancellingAndBackspacingPreserveTheExistingSelection() async throws {
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
        try send("\u{1b}", to: view)
        #expect(!view.isWordJumpActive)
        #expect(view.currentSelection?.range(at: 0, on: page) == originalRange)
    }

    @Test(arguments: ["", "al"]) @MainActor
    func unmatchedInputExitsWordSelectionAndReportsAToast(prefix: String) async throws {
        let (window, view) = try await makeReader(pages: [[("alpha beta", NSPoint(x: 72, y: 650))]])
        defer { view.cancelWordJump(); window.close() }
        let page = try #require(view.document?.page(at: 0))
        let original = (try #require(page.string) as NSString).range(of: "beta")
        view.setCurrentSelection(page.selection(for: original), animate: false)
        view.beginWordJumpCommand()
        for letter in prefix { try send(String(letter), to: view) }

        try send("9", to: view)

        #expect(!view.isWordJumpActive)
        #expect(view.currentSelection?.range(at: 0, on: page) == original)
        let toast = try #require(window.contentView?.superview?.subviews.compactMap { $0 as? ToastView }.first)
        #expect(toast.message == AppUILanguage.saved().text(.wordJumpNoMatch))
        #expect(toast.kind == .warning)
        #expect(toast.autoDismiss)
        #expect(!view.handleWordJumpKey(try event("a", in: window)))
    }

    @Test(arguments: ["escape", "cancel", "viewport", "replacement"]) @MainActor
    func cancellingWordSelectionOnlyDismissesItsOwnHint(action: String) async throws {
        let (window, view) = try await makeReader(pages: [[("alpha beta", NSPoint(x: 72, y: 650))]])
        defer { view.cancelWordJump(); window.close() }
        view.beginWordJumpCommand()
        let hint = try #require(window.contentView?.superview?.subviews.compactMap { $0 as? ToastView }.first)
        switch action {
        case "escape": try send("\u{1b}", to: view)
        case "viewport": view.setFrameSize(NSSize(width: 700, height: 400)); view.layout()
        case "replacement":
            view.showNotification("Another operation finished")
            view.cancelWordJump()
        default: view.cancelWordJump()
        }
        #expect(!view.isWordJumpActive)
        #expect(hint.superview == nil)
        let toasts = window.contentView?.superview?.subviews.compactMap { $0 as? ToastView } ?? []
        #expect(toasts.map(\.message) == (action == "replacement" ? ["Another operation finished"] : []))
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
        let target = try #require(controller.targets.first { $0.word == "brokenword" })
        let text = try #require(page.string) as NSString
        for (count, prefix) in [(2, "br"), (99, "broken")] {
            let prefixSelection = try #require(page.selection(for: text.range(of: prefix)))
            let expected = try #require(view.viewRect(for: prefixSelection.bounds(for: page), on: page))
            let area = try #require(target.labelArea(characterCount: count, in: view))
            #expect(area.characterCount == prefix.count)
            expectSameRect(area.rect, expected)
        }
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
        let prefixSelection = try #require(page.selection(for: NSRange(location: suffixRange.location, length: 2)))
        let expected = try #require(view.viewRect(for: prefixSelection.bounds(for: page), on: page))
        let area = try #require(target.labelArea(characterCount: 2, in: view))
        #expect(area.characterCount == 2)
        expectSameRect(area.rect, expected)
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
            let bounds = try #require(target.selection).bounds(for: page)
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
            let text = try #require(page.string) as NSString
            let prefix = NSRange(location: text.range(of: target.word).location, length: 2)
            let prefixSelection = try #require(page.selection(for: prefix))
            let prefixBounds = try #require(view.viewRect(for: prefixSelection.bounds(for: page), on: page))
            let area = try #require(target.labelArea(characterCount: 2, in: view))
            #expect(area.characterCount == 2)
            expectSameRect(area.rect, prefixBounds)
        }
    }

    @Test(arguments: ["scroll", "resize", "document"], [false, true]) @MainActor
    func changingTheViewportOrDocumentCancelsStaleLabels(change: String, lookupAfterSelection: Bool) async throws {
        let defaults = UserDefaults.standard
        let previousDictionary = defaults.object(forKey: AppPreferenceKeys.dictionaryPath)
        let dictionary = FileManager.default.temporaryDirectory.appendingPathComponent("VellumWordJump-\(UUID().uuidString).mdx")
        defer {
            if let previousDictionary { defaults.set(previousDictionary, forKey: AppPreferenceKeys.dictionaryPath) }
            else { defaults.removeObject(forKey: AppPreferenceKeys.dictionaryPath) }
            try? FileManager.default.removeItem(at: dictionary)
        }
        try MDictFixture(entries: [("alpha", Data("<p>Definition</p>".utf8))]).data.write(to: dictionary)
        defaults.set(dictionary.path, forKey: AppPreferenceKeys.dictionaryPath)
        let (window, view) = try await makeReader(pages: [
            [("alpha", NSPoint(x: 72, y: 650))],
            [("beta", NSPoint(x: 72, y: 650))]
        ])
        defer { window.close() }
        if lookupAfterSelection { view.vimLookupDictionary() } else { view.beginWordJumpCommand() }
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
        #expect(view.dictionaryAccessTask == nil)
        #expect(view.dictionaryPopover == nil)
    }

    @Test @MainActor
    func pagesWithoutTextDoNotCaptureKeys() async throws {
        let (window, view) = try await makeReader(pages: [[]])
        defer { window.close() }
        view.beginWordJumpCommand()
        #expect(!view.isWordJumpActive)
        #expect(view.wordJumpController?.targets.isEmpty == true)
        #expect(!view.handleWordJumpKey(try event("j", in: window)))
        #expect(view.currentSelection == nil)
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

    private func expectSameRect(_ actual: NSRect, _ expected: NSRect) {
        #expect(abs(actual.minX - expected.minX) < 0.000001)
        #expect(abs(actual.minY - expected.minY) < 0.000001)
        #expect(abs(actual.width - expected.width) < 0.000001)
        #expect(abs(actual.height - expected.height) < 0.000001)
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
