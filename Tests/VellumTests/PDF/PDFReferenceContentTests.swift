@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF reference content")
struct PDFReferenceContentTests {
    @Test(arguments: [0, 90, 180, 270])
    func aCrossPageReferenceCombinesOnlyTheSelectedFragments(rotation: Int) throws {
        let document = try makeTextPDF(pages: [
            [("previous entry", NSPoint(x: 80, y: 260)), ("Engram first part", NSPoint(x: 80, y: 180)),
             ("unrelated row", NSPoint(x: 260, y: 148))],
            [("Engram continuation", NSPoint(x: 90, y: 700)), ("next entry", NSPoint(x: 80, y: 620))]
        ])
        let first = try #require(document.page(at: 0))
        let second = try #require(document.page(at: 1))
        for page in [first, second] {
            page.setBounds(NSRect(x: 40, y: 50, width: 500, height: 700), for: .cropBox)
        }
        first.rotation = rotation
        second.rotation = rotation
        let firstBounds = first.bounds(for: .cropBox)
        let secondBounds = second.bounds(for: .cropBox)
        let firstCrop = NSRect(x: 76, y: 176, width: 250, height: 32)
        let secondCrop = NSRect(x: 86, y: 696, width: 280, height: 32)
        let redBounds = NSRect(x: 240, y: 180, width: 20, height: 16)
        let blueBounds = NSRect(x: 300, y: 700, width: 20, height: 16)
        for (page, bounds, color, visible) in [
            (first, redBounds, NSColor.red, true),
            (second, blueBounds, NSColor.blue, true),
            (first, NSRect(x: 260, y: 148, width: 60, height: 16), NSColor.green, true),
            (first, NSRect(x: 280, y: 180, width: 20, height: 16), NSColor.green, false)
        ] {
            let highlight = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            highlight.color = color
            highlight.quadrilateralPoints = HighlightGeometry.quadrilateralPoints(for: bounds)
            highlight.shouldDisplay = visible
            page.addAnnotation(highlight)
        }
        let destination = PDFDestination(page: first, at: NSPoint(x: 80, y: 200))

        let content = try #require(PDFReferenceContent(document: document, destination: destination,
            crop: firstCrop, fitsEntireCrop: true, continuation: (second, secondCrop)))

        #expect(content.sourcePage === first)
        #expect(content.destination.page === first)
        #expect(content.pageNumber == 1)
        #expect(content.displayDocument.pageCount == 1)
        let firstVisible = PDFPageDisplayGeometry(page: first, box: .cropBox).rect(forPageRect: firstCrop)
        let secondVisible = PDFPageDisplayGeometry(page: second, box: .cropBox).rect(forPageRect: secondCrop)
        let expected = NSRect(x: 0, y: 0,
                              width: max(firstVisible.maxX, secondVisible.maxX) - min(firstVisible.minX, secondVisible.minX),
                              height: firstVisible.height + secondVisible.height + 4)
        #expect(content.displayPage.bounds(for: .cropBox) == expected)
        let combined = try #require(content.displayPage.string)
        #expect(combined.contains("Engram first part"))
        #expect(combined.contains("Engram continuation"))
        let upper = try #require(content.displayDocument.findString("Engram first part", withOptions: []).first)
        let lower = try #require(content.displayDocument.findString("Engram continuation", withOptions: []).first)
        #expect(upper.bounds(for: content.displayPage).minY > lower.bounds(for: content.displayPage).maxY)
        let visible = content.displayPage.bounds(for: .cropBox)
        #expect(visible.contains(upper.bounds(for: content.displayPage)))
        #expect(visible.contains(lower.bounds(for: content.displayPage)))
        if rotation == 0 {
            #expect(abs(lower.bounds(for: content.displayPage).minX - upper.bounds(for: content.displayPage).minX - 10) < 0.1)
        }
        if rotation == 0 {
            for text in ["previous entry", "next entry"] {
                for selection in content.displayDocument.findString(text, withOptions: []) {
                    #expect(selection.bounds(for: content.displayPage).intersection(visible).isEmpty)
                }
            }
        }
        #expect(first.bounds(for: .cropBox) == firstBounds)
        #expect(second.bounds(for: .cropBox) == secondBounds)
        #expect(first.document === document)
        #expect(second.document === document)
        #expect(content.isValid(in: document))
        let raster = try #require(CGContext(data: nil, width: Int(expected.width), height: Int(expected.height),
            bitsPerComponent: 8, bytesPerRow: Int(expected.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        raster.setFillColor(NSColor.white.cgColor)
        raster.fill(expected)
        raster.drawPDFPage(try #require(content.displayPage.pageRef))
        let pixels = try #require(raster.data).assumingMemoryBound(to: UInt8.self)
        // Bitmap rows start at the top; PDF coordinates start at the bottom.
        for (page, bounds, fragment, outputY, channel) in [
            (first, redBounds, firstVisible, secondVisible.height + 4, 0),
            (second, blueBounds, secondVisible, CGFloat(0), 2)
        ] {
            let center = PDFPageDisplayGeometry(page: page, box: .cropBox)
                .point(forPagePoint: NSPoint(x: bounds.midX, y: bounds.midY))
            let x = Int(center.x - min(firstVisible.minX, secondVisible.minX))
            let y = Int(center.y - fragment.minY + outputY)
            let offset = (Int(expected.height) - y - 1) * raster.bytesPerRow + x * 4
            #expect(pixels[offset + channel] > 180)
            #expect(pixels[offset + 1] < 140)
            #expect(pixels[offset + (channel == 0 ? 2 : 0)] < 140)
        }
        #expect((0..<Int(expected.height)).allSatisfy { y in
            (0..<Int(expected.width)).allSatisfy { x in
                let offset = y * raster.bytesPerRow + x * 4
                return Int(pixels[offset + 1]) <= min(Int(pixels[offset]), Int(pixels[offset + 2])) + 40
            }
        })
        func inkRows(_ range: Range<Int>) -> Int {
            range.filter { y in
                (0..<Int(expected.width)).contains { x in
                    pixels[(Int(expected.height) - y - 1) * raster.bytesPerRow + x * 4] < 128
                }
            }.count
        }
        #expect(inkRows(0..<Int(secondVisible.height)) > 0)
        #expect(inkRows(Int(secondVisible.height + 4)..<Int(expected.height)) > 0)
        #expect(inkRows(Int(secondVisible.height)..<Int(secondVisible.height + 4)) == 0)
        if rotation == 0 {
            #expect((0..<32).allSatisfy { y in
                (210..<220).allSatisfy { x in
                    pixels[(Int(expected.height) - y - 1) * raster.bytesPerRow + x * 4] > 250
                }
            })
        }
        document.removePage(at: 1)
        #expect(!content.isValid(in: document))
    }

    @Test
    func aCrossPageReferenceRejectsInvalidContinuationBoundsAndForeignPages() throws {
        let document = try makeTextPDF(pages: [[("first", NSPoint(x: 80, y: 180))], []])
        let first = try #require(document.page(at: 0))
        let second = try #require(document.page(at: 1))
        let foreignDocument = try makeTextPDF(pages: [[]])
        let foreign = try #require(foreignDocument.page(at: 0))
        let destination = PDFDestination(page: first, at: NSPoint(x: 80, y: 200))
        let crop = NSRect(x: 76, y: 176, width: 250, height: 32)

        #expect(PDFReferenceContent(document: document, destination: destination, crop: crop,
            continuation: (foreign, crop)) == nil)
        #expect(PDFReferenceContent(document: document, destination: destination, crop: crop,
            continuation: (second, .zero)) == nil)
        #expect(PDFReferenceContent(document: document, destination: destination, crop: crop,
            continuation: (second, NSRect(x: 0, y: 0, width: CGFloat.infinity, height: 40))) == nil)
        #expect(PDFReferenceContent(document: document, destination: destination,
            continuation: (second, crop)) == nil)
    }

    @Test
    func croppedReferenceOwnsACopyAndRejectsPagesFromAnotherDocument() throws {
        let document = try makeTextPDF(pages: [[("reference text", NSPoint(x: 130, y: 400))]])
        let source = try #require(document.page(at: 0))
        let originalCrop = NSRect(x: 100, y: 150, width: 360, height: 500)
        source.setBounds(originalCrop, for: .cropBox)
        source.rotation = 90
        let originalPageRefCrop = try #require(source.pageRef).getBoxRect(.cropBox)
        let originalLink = PDFAnnotation(bounds: NSRect(x: 130, y: 400, width: 120, height: 20),
                                         forType: .link, withProperties: nil)
        originalLink.url = URL(string: "https://example.com/reference")
        source.addAnnotation(originalLink)
        let requestedCrop = NSRect(x: 80, y: 350, width: 300, height: 200)
        let destination = PDFDestination(page: source, at: NSPoint(x: 200, y: 450))

        let content = try #require(PDFReferenceContent(document: document, destination: destination, crop: requestedCrop))

        #expect(content.sourcePage === source)
        #expect(content.sourceDocument === document)
        #expect(content.pageNumber == 1)
        #expect(content.displayPage !== source)
        #expect(content.displayDocument !== document)
        #expect(content.displayPage.document === content.displayDocument)
        #expect(content.displayPage.bounds(for: .cropBox) == requestedCrop.intersection(originalCrop))
        #expect(content.displayPage.rotation == 90)
        #expect(content.displayPage.string == source.string)
        #expect(source.bounds(for: .cropBox) == originalCrop)
        #expect(try #require(source.pageRef).getBoxRect(.cropBox) == originalPageRefCrop)
        #expect(source.document === document)
        #expect(document.page(at: 0) === source)
        #expect(originalLink.page === source)
        #expect(source.annotations.contains { $0 === originalLink })
        let copiedLink = try #require(content.displayPage.annotations.first)
        #expect(copiedLink !== originalLink)
        #expect(copiedLink.page === content.displayPage)
        #expect(copiedLink.url == originalLink.url)
        #expect(content.isValid(in: document))
        let otherDocument = PDFDocument()
        #expect(!content.isValid(in: otherDocument))
        #expect(PDFReferenceContent(document: otherDocument, destination: destination) == nil)
        #expect(PDFReferenceContent(document: document, destination: destination,
                                    crop: NSRect(x: -100, y: -100, width: 20, height: 20)) == nil)
        document.removePage(at: 0)
        otherDocument.insert(source, at: 0)
        #expect(!content.isValid(in: document))
        #expect(!content.isValid(in: otherDocument))
    }

    @Test(arguments: [0, 90, 180, 270])
    func unspecifiedAndOutOfBoundsDestinationsStayInsideTheDisplayedCrop(rotation: Int) throws {
        let document = try makeTextPDF(pages: [[]])
        let page = try #require(document.page(at: 0))
        let crop = NSRect(x: 100, y: 150, width: 360, height: 500)
        page.setBounds(crop, for: .cropBox)
        page.rotation = rotation
        let expectedTop: NSPoint
        switch rotation {
        case 90: expectedTop = NSPoint(x: crop.minX, y: crop.midY)
        case 180: expectedTop = NSPoint(x: crop.midX, y: crop.minY)
        case 270: expectedTop = NSPoint(x: crop.maxX, y: crop.midY)
        default: expectedTop = NSPoint(x: crop.midX, y: crop.maxY)
        }

        let unspecified = NSPoint(x: CGFloat(Float.greatestFiniteMagnitude), y: CGFloat(Float.greatestFiniteMagnitude))
        #expect(PDFReferenceContent.normalizedPoint(unspecified, on: page) == expectedTop)
        #expect(PDFReferenceContent.normalizedPoint(NSPoint(x: CGFloat.nan, y: CGFloat.infinity), on: page) == expectedTop)
        let content = try #require(PDFReferenceContent(document: document, destination: PDFDestination(page: page, at: unspecified)))
        #expect(content.destination.point == expectedTop)
        let interior = NSPoint(x: crop.midX, y: crop.midY)
        #expect(PDFReferenceContent.normalizedPoint(interior, on: page) == interior)
        #expect(PDFReferenceContent.normalizedPoint(NSPoint(x: -900, y: 3000), on: page)
                == NSPoint(x: crop.minX, y: crop.maxY))
        #expect(page.bounds(for: .cropBox) == crop)
    }

    @Test
    func partiallySpecifiedDestinationsRetainTheirKnownAxis() throws {
        let document = try makeTextPDF(pages: [[]])
        let page = try #require(document.page(at: 0))
        let missing = CGFloat(Float.greatestFiniteMagnitude)
        #expect(PDFReferenceContent.normalizedPoint(NSPoint(x: missing, y: 300), on: page)
                == NSPoint(x: 306, y: 300))
        #expect(PDFReferenceContent.normalizedPoint(NSPoint(x: 120, y: missing), on: page)
                == NSPoint(x: 120, y: 792))
    }

    @Test
    func threeFragmentsRemainOrderedAndInvalidatedWithTheirSourcePages() throws {
        let document = try makeTextPDF(pages: [
            [("First fragment", NSPoint(x: 80, y: 600))],
            [("Second fragment", NSPoint(x: 80, y: 600))],
            [("Third fragment", NSPoint(x: 80, y: 600))]
        ])
        let pages = try (0..<3).map { try #require(document.page(at: $0)) }
        let crop = CGRect(x: 76, y: 596, width: 240, height: 30)
        let original = pages.map { $0.bounds(for: .cropBox) }
        let content = try #require(PDFReferenceContent(document: document,
            destination: PDFDestination(page: pages[0], at: crop.origin), crop: crop,
            continuation: (pages[1], crop), additionalFragments: [(pages[2], crop)]))
        #expect(content.displayPage.bounds(for: .cropBox).height == 98)
        let positions = try ["First fragment", "Second fragment", "Third fragment"].map { text in
            let selection = try #require(content.displayDocument.findString(text, withOptions: []).first)
            return selection.bounds(for: content.displayPage)
        }
        #expect(positions[0].minY > positions[1].maxY)
        #expect(positions[1].minY > positions[2].maxY)
        #expect(pages.map { $0.bounds(for: .cropBox) } == original)
        #expect(content.isValid(in: document))
        document.removePage(at: 2)
        #expect(!content.isValid(in: document))
    }

    @Test(arguments: [true, false])
    func readingFragmentsUseTheirWidthInsteadOfTheGapBetweenSourceColumns(section: Bool) throws {
        let document = try makeTextPDF(pages: [[
            ("Left column text", NSPoint(x: 80, y: 200)),
            ("Right column text", NSPoint(x: 340, y: 600))
        ]])
        let page = try #require(document.page(at: 0))
        let content = try #require(PDFReferenceContent(document: document,
            destination: PDFDestination(page: page, at: NSPoint(x: 80, y: 210)),
            crop: CGRect(x: 76, y: 196, width: 240, height: 30),
            title: section ? .sectionPreview("2") : .tablePreview("2"),
            continuation: (page, CGRect(x: 336, y: 596, width: 240, height: 30))))
        #expect(content.displayPage.bounds(for: .cropBox).width == 240)
        let left = try #require(content.displayDocument.findString("Left column text", withOptions: []).first)
        let right = try #require(content.displayDocument.findString("Right column text", withOptions: []).first)
        #expect(abs(left.bounds(for: content.displayPage).minX - right.bounds(for: content.displayPage).minX) < 0.1)
    }
}
