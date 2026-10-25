import CoreGraphics
import Foundation
@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@Suite("PDF graphic bounds")
struct PDFGraphicBoundsTests {
    @Test
    func imageTransformsRestoreBetweenGraphicsStates() throws {
        let document = try graphicBoundsDocument(
            content: "q 120 0 0 80 40 50 cm /Image Do Q q 30 0 0 25 210 320 cm /Image Do Q",
            xObjects: [("Image", graphicBoundsImage)])
        let page = try #require(document.page(at: 1))

        let regions = PDFGraphicBounds.regions(on: page)

        #expect(regions.count == 2)
        #expect(regions.contains(CGRect(x: 40, y: 50, width: 120, height: 80)))
        #expect(regions.contains(CGRect(x: 210, y: 320, width: 30, height: 25)))
    }

    @Test
    func nestedFormsComposeMatricesAndInheritResources() throws {
        let inner = graphicBoundsStream(
            dictionary: "/Type /XObject /Subtype /Form /BBox [0 0 20 10] /Matrix [1 0 0 1 2 3]",
            content: "0 0 20 10 re f")
        let outer = graphicBoundsStream(
            dictionary: "/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Matrix [1 0 0 1 10 20]",
            content: "q 1 0 0 1 5 7 cm /Inner Do Q")
        let document = try graphicBoundsDocument(
            content: "q 2 0 0 3 40 50 cm /Outer Do Q",
            xObjects: [("Inner", inner), ("Outer", outer)])
        let page = try #require(document.page(at: 1))

        let regions = PDFGraphicBounds.regions(on: page)

        #expect(regions.count == 2)
        #expect(regions.contains(CGRect(x: 60, y: 110, width: 200, height: 300)))
        #expect(regions.contains(CGRect(x: 74, y: 140, width: 40, height: 30)))
    }

    @Test
    func separateFormsRemainSeparateRegions() throws {
        let left = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [40 400 180 520]",
                                       content: "40 400 140 120 re f")
        let right = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [320 400 560 520]",
                                        content: "320 400 240 120 re f")
        let document = try graphicBoundsDocument(content: "/Left Do /Right Do",
                                                 xObjects: [("Left", left), ("Right", right)])
        let page = try #require(document.page(at: 1))

        let regions = PDFGraphicBounds.regions(on: page)

        #expect(regions.count == 2)
        #expect(regions.contains(CGRect(x: 40, y: 400, width: 140, height: 120)))
        #expect(regions.contains(CGRect(x: 320, y: 400, width: 240, height: 120)))
    }

    @Test
    func pageSizedWrapperIsDiscardedWhileItsFigureRemains() throws {
        let wrapper = graphicBoundsStream(
            dictionary: "/Type /XObject /Subtype /Form /BBox [5 5 595 795] /Resources << /XObject << /Figure 6 0 R >> >>",
            content: "/Figure Do")
        let figure = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [50 400 350 650]",
                                         content: "50 400 300 250 re f")
        let document = try graphicBoundsDocument(content: "/Wrapper Do",
                                                 xObjects: [("Wrapper", wrapper), ("Figure", figure)])
        let page = try #require(document.page(at: 1))

        #expect(PDFGraphicBounds.regions(on: page) == [CGRect(x: 50, y: 400, width: 300, height: 250)])
    }

    @Test
    func graphicsIntersectCropBoxInUnrotatedPageCoordinates() throws {
        let document = try graphicBoundsDocument(
            content: "q 100 0 0 100 50 650 cm /Image Do Q q 20 0 0 20 0 0 cm /Image Do Q q 50 0 0 60 200 300 cm /Image Do Q",
            xObjects: [("Image", graphicBoundsImage)],
            cropBox: "[100 100 500 700]", rotation: 90)
        let page = try #require(document.page(at: 1))

        let regions = PDFGraphicBounds.regions(on: page)

        #expect(regions.count == 2)
        #expect(regions.contains(CGRect(x: 100, y: 650, width: 50, height: 50)))
        #expect(regions.contains(CGRect(x: 200, y: 300, width: 50, height: 60)))
    }

    @Test(arguments: ["W", "W*"])
    func explicitClippingRejectsUnreliableGraphicsAndRestoresAfterQ(clipOperator: String) throws {
        let figure = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [40 400 350 650]",
                                         content: "q 310 0 0 250 40 400 cm /Image Do Q")
        let document = try graphicBoundsDocument(
            content: "q 40 400 m 180 400 l 120 500 l h \(clipOperator) n /Figure Do q 100 0 0 80 100 400 cm /Image Do Q Q q 100 0 0 80 420 200 cm /Image Do Q",
            xObjects: [("Figure", figure), ("Image", graphicBoundsImage)])
        let page = try #require(document.page(at: 1))

        #expect(PDFGraphicBounds.regions(on: page) == [CGRect(x: 420, y: 200, width: 100, height: 80)])
    }

    @Test(arguments: ["W", "W*"])
    func rectangularClipInsideAFormUsesTheClippedImageInsteadOfItsLargeWrapper(clipOperator: String) throws {
        let figure = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [40 400 350 650]",
                                         content: "q 40 500 310 150 re \(clipOperator) n q 310 0 0 250 40 400 cm /Image Do Q Q")
        let document = try graphicBoundsDocument(content: "/Figure Do",
                                                 xObjects: [("Figure", figure), ("Image", graphicBoundsImage)])
        let page = try #require(document.page(at: 1))

        #expect(PDFGraphicBounds.regions(on: page) == [CGRect(x: 40, y: 500, width: 310, height: 150)])
    }

    @Test(arguments: [false, true])
    func exportedFourCornerClipAcceptsFloatingPointJitterAndImplicitClosure(closed: Bool) throws {
        let figure = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [0 0 960 700]",
                                         content: "q -.000030518 540 m 960 540 l 960 -.000061035 l -.000030518 .000061035 l \(closed ? "h" : "") W* n q 960 0 0 700 0 0 cm /Image Do Q Q")
        let document = try graphicBoundsDocument(content: "q 0.5 0 0 0.5 40 100 cm /Figure Do Q",
                                                 xObjects: [("Figure", figure), ("Image", graphicBoundsImage)])
        let page = try #require(document.page(at: 1))

        #expect(PDFGraphicBounds.regions(on: page) == [CGRect(x: 40, y: 100, width: 480, height: 270)])
    }

    @Test
    func unknownClipInsideAFormDiscardsItsWholeSubtreeIncludingEnclosingWrappers() throws {
        let parent = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [20 380 380 680]",
                                         content: "/Figure Do")
        let figure = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [40 400 350 650]",
                                         content: "/Good Do q 40 400 m 180 400 l 120 500 l h W n /Image Do Q /Good Do")
        let good = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [50 500 300 580]",
                                       content: "50 500 250 80 re f")
        let document = try graphicBoundsDocument(
            content: "/Parent Do q 100 0 0 80 420 200 cm /Image Do Q",
            xObjects: [("Parent", parent), ("Figure", figure), ("Good", good), ("Image", graphicBoundsImage)])
        let page = try #require(document.page(at: 1))

        #expect(PDFGraphicBounds.regions(on: page) == [CGRect(x: 420, y: 200, width: 100, height: 80)])
    }
}

@MainActor
@Suite("PDF figure previews")
struct PDFFigurePreviewTests {
    @Test(arguments: ["Figure ", "Fig. ", "图 ", "Figures 6 and "])
    func figureNumberRecognizesPrefixOutsideTheLinkedDigits(prefix: String) throws {
        let document = try makeTextPDF(pages: [[("See \(prefix)7 for the architecture.", NSPoint(x: 40, y: 650))]])
        let page = try #require(document.page(at: 0))
        let annotation = try linkedText("7", on: page)

        #expect(PDFFigurePreview.number(for: annotation) == "7")
        let prefixBounds = try textBounds(prefix.trimmingCharacters(in: .whitespaces), on: page)
        #expect(annotation.bounds.minX > prefixBounds.maxX)
    }

    @Test(arguments: ["There are 7 examples.", "See reference [7].", "Equation (7) gives the result.",
                      "Section 7 describes the method.", "Table 7 reports accuracy.", "Figure 6 has 7 inputs."])
    func ordinaryNumbersReferencesAndEquationsAreNotFigureLinks(text: String) throws {
        let document = try makeTextPDF(pages: [[(text, NSPoint(x: 40, y: 650))]])
        let page = try #require(document.page(at: 0))

        #expect(PDFFigurePreview.number(for: try linkedText("7", on: page)) == nil)
    }

    @Test(arguments: ["-", "\u{00AD}"])
    func aFigurePrefixSplitAcrossLinesStillIdentifiesTheLinkedNumber(hyphen: String) throws {
        let document = try makeTextPDF(pages: [[("See Fig\(hyphen)", NSPoint(x: 40, y: 650)),
                                               ("ure 2 for the comparison.", NSPoint(x: 40, y: 628))]])
        let page = try #require(document.page(at: 0))

        #expect(PDFFigurePreview.number(for: try linkedText("2", on: page)) == "2")
    }

    @Test
    func glyphsAtTheGraphicEdgeHaveTheSamePaddingAsTheCaption() throws {
        let figure = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [310 420 550 650]",
                                         content: "310 420 240 230 re f\nBT /F1 12 Tf 370 642 Td (Chart title) Tj ET")
        let data = graphicBoundsData(
            content: "/Figure Do\nBT /F1 12 Tf 310 402 Td (Figure 2: A comparison.) Tj ET",
            xObjects: [("Figure", figure)])
        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))
        let title = try textBounds("Chart title", on: page)
        try #require(title.maxY > 650 && title.maxY < 652)

        let crop = try #require(PDFFigurePreview.crop(number: "2", destination: PDFDestination(page: page, at: CGPoint(x: 430, y: 650))))

        #expect(crop.contains(title))
        #expect(crop.maxY <= 652)
    }

    @Test(arguments: [CGFloat(420), CGFloat(650)])
    func vectorFigureIncludesItsWholeCaptionAndExcludesTheAdjacentBody(anchorY: CGFloat) throws {
        let document = try figureDocument()
        let page = try #require(document.page(at: 0))
        let destination = PDFDestination(page: page, at: CGPoint(x: 430, y: anchorY))

        let crop = try #require(PDFFigurePreview.crop(number: "2", destination: destination))

        #expect(crop.contains(CGRect(x: 310, y: 420, width: 240, height: 230)))
        #expect(crop.contains(try textBounds("Figure 2: A vector comparison.", on: page)))
        #expect(crop.contains(try textBounds("Second caption line.", on: page)))
        #expect(!crop.intersects(try textBounds("The body remains in the left column.", on: page)))
        #expect(!crop.intersects(try textBounds("Body paragraph below the caption.", on: page)))
        #expect(crop.minX >= 306)
        #expect(crop.maxX <= 554)
        #expect(crop.maxY <= 654)
    }

    @Test
    func sideBySideFiguresOnlyIncludeTheMatchingGraphicAndCaption() throws {
        let left = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [40 450 275 650]",
                                       content: "40 450 235 200 re f")
        let right = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [325 450 560 650]",
                                        content: "325 450 235 200 re f")
        let data = graphicBoundsData(
            content: "/Left Do /Right Do\nBT /F1 12 Tf 40 432 Td (Figure 6: First comparison.) Tj 0 -14 Td (Left caption continues.) Tj ET\nBT /F1 12 Tf 325 432 Td (Figure 7: Second comparison.) Tj 0 -14 Td (Right caption continues.) Tj ET",
            xObjects: [("Left", left), ("Right", right)])
        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))

        let leftCrop = try #require(PDFFigurePreview.crop(number: "6", destination: PDFDestination(page: page, at: CGPoint(x: 150, y: 650))))
        let rightCrop = try #require(PDFFigurePreview.crop(number: "7", destination: PDFDestination(page: page, at: CGPoint(x: 440, y: 450))))

        #expect(leftCrop.contains(CGRect(x: 40, y: 450, width: 235, height: 200)))
        #expect(leftCrop.contains(try textBounds("Figure 6: First comparison.", on: page)))
        #expect(leftCrop.contains(try textBounds("Left caption continues.", on: page)))
        #expect(!leftCrop.intersects(try textBounds("Figure 7: Second comparison.", on: page)))
        #expect(!leftCrop.intersects(try textBounds("Right caption continues.", on: page)))
        #expect(leftCrop.maxX < 300)
        #expect(rightCrop.contains(CGRect(x: 325, y: 450, width: 235, height: 200)))
        #expect(!rightCrop.intersects(try textBounds("Figure 6: First comparison.", on: page)))
        #expect(!rightCrop.intersects(try textBounds("Left caption continues.", on: page)))
        #expect(rightCrop.contains(try textBounds("Figure 7: Second comparison.", on: page)))
        #expect(rightCrop.contains(try textBounds("Right caption continues.", on: page)))
        #expect(rightCrop.minX > 300)
    }

    @Test(arguments: [false, true])
    func aSharedCaptionKeepsBothPanelsAndExcludesAnUnrelatedGraphic(centeredCaption: Bool) throws {
        let left = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [40 450 280 650]",
                                       content: "40 450 240 200 re f")
        let right = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [283 450 523 650]",
                                        content: "283 450 240 200 re f")
        let unrelated = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [40 700 523 760]",
                                            content: "40 700 483 60 re f")
        let caption = centeredCaption
            ? "Figure 2: Comparison of the left and right panels."
            : "Figure 2: Two panels share this caption; each panel is narrower than half of the full caption."
        let captionX = centeredCaption ? 153 : 40
        let data = graphicBoundsData(
            content: "/Left Do /Right Do /Unrelated Do\nBT /F1 12 Tf \(captionX) 432 Td (\(caption)) Tj ET\nBT /F1 12 Tf 40 418 Td (Second caption line.) Tj 0 -38 Td (Body paragraph after the figure.) Tj ET",
            xObjects: [("Left", left), ("Right", right), ("Unrelated", unrelated)])
        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))

        let crop = try #require(PDFFigurePreview.crop(number: "2", destination: PDFDestination(page: page, at: CGPoint(x: 40, y: 650))))

        #expect(crop.contains(CGRect(x: 40, y: 450, width: 240, height: 200)))
        #expect(crop.contains(CGRect(x: 283, y: 450, width: 240, height: 200)))
        #expect(crop.contains(try textBounds(caption, on: page)))
        #expect(crop.contains(try textBounds("Second caption line.", on: page)))
        #expect(!crop.intersects(CGRect(x: 40, y: 700, width: 483, height: 60)))
        #expect(!crop.intersects(try textBounds("Body paragraph after the figure.", on: page)))
    }

    @Test
    func aCenteredGraphicAcceptsAnAnchorAtTheWideCaptionMargin() throws {
        let figure = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [130 450 410 650]",
                                         content: "130 450 280 200 re f")
        let caption = "Figure 2: A centered graphic with a caption extending to the left document margin."
        let continuation = ["The second caption line belongs to the same comparison.",
                            "The third caption line explains the plotted data.",
                            "The final caption line remains visible."]
        let data = graphicBoundsData(
            content: "/Figure Do\nBT /F1 12 Tf 40 432 Td (\(caption)) Tj 0 -14 Td (\(continuation[0])) Tj 0 -14 Td (\(continuation[1])) Tj 0 -14 Td (\(continuation[2])) Tj 0 -44 Td (Body paragraph after the caption.) Tj ET",
            xObjects: [("Figure", figure)])
        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))

        let crop = try #require(PDFFigurePreview.crop(number: "2", destination: PDFDestination(page: page, at: CGPoint(x: 40, y: 650))))

        #expect(crop.contains(CGRect(x: 130, y: 450, width: 280, height: 200)))
        for line in [caption] + continuation {
            #expect(crop.contains(try textBounds(line, on: page)))
        }
        #expect(!crop.intersects(try textBounds("Body paragraph after the caption.", on: page)))
        #expect(PDFFigurePreview.crop(number: "2", destination: PDFDestination(page: page, at: CGPoint(x: 40, y: 695))) == nil)
    }

    @Test
    func captionCanExtendPastTheGraphicAndStopsBeforeTheNextFigure() throws {
        let figure = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [310 420 550 650]",
                                         content: "310 420 240 230 re f")
        let caption = "Figure 2: A comparison with a wider caption."
        let data = graphicBoundsData(
            content: "/Figure Do\nBT /F1 12 Tf 290 402 Td (\(caption)) Tj 0 -14 Td (Second caption line.) Tj 0 -14 Td (Figure 3: A different figure.) Tj ET",
            xObjects: [("Figure", figure)])
        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))
        let crop = try #require(PDFFigurePreview.crop(number: "2", destination: PDFDestination(page: page, at: CGPoint(x: 430, y: 650))))

        #expect(crop.contains(try textBounds(caption, on: page)))
        #expect(crop.contains(try textBounds("Second caption line.", on: page)))
        #expect(!crop.intersects(try textBounds("Figure 3: A different figure.", on: page)))
    }

    @Test
    func centeredCaptionCanContinueWithAWiderLine() throws {
        let figure = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [310 420 550 650]",
                                         content: "310 420 240 230 re f")
        let continuation = "An explanatory caption wider than the chart."
        let data = graphicBoundsData(
            content: "/Figure Do\nBT /F1 12 Tf 370 402 Td (Figure 2: Plot.) Tj ET\nBT /F1 12 Tf 290 388 Td (\(continuation)) Tj ET",
            xObjects: [("Figure", figure)])
        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))
        let crop = try #require(PDFFigurePreview.crop(number: "2", destination: PDFDestination(page: page, at: CGPoint(x: 430, y: 650))))

        #expect(crop.contains(try textBounds("Figure 2: Plot.", on: page)))
        #expect(crop.contains(try textBounds(continuation, on: page)))
    }

    @Test
    func captionIncludesAShortFinalTableReference() throws {
        let figure = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [310 420 550 650]",
                                         content: "310 420 240 230 re f")
        let data = graphicBoundsData(
            content: "/Figure Do\nBT /F1 12 Tf 310 402 Td (Figure 2: Numerical results in) Tj 0 -14 Td /F1 6 Tf (Table 13.) Tj ET\nBT /F1 12 Tf 310 354 Td (Body paragraph after the caption.) Tj ET",
            xObjects: [("Figure", figure)])
        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))
        let crop = try #require(PDFFigurePreview.crop(number: "2", destination: PDFDestination(page: page, at: CGPoint(x: 430, y: 650))))

        #expect(crop.contains(try textBounds("Table 13.", on: page)))
        #expect(!crop.intersects(try textBounds("Body paragraph after the caption.", on: page)))
    }

    @Test(arguments: [false, true])
    func detachedLegendsBelongToTheirPanelsWithoutTheNextGraphic(above: Bool) throws {
        let legendY = above ? 640 : 432
        let captionY = above ? 432 : 410
        let panel = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [80 450 480 630]",
                                        content: "80 450 400 180 re f")
        let legend = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [150 \(legendY) 410 \(legendY + 14)]",
                                         content: "150 \(legendY) 260 14 re S")
        let unrelated = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [80 700 480 740]",
                                            content: "80 700 400 40 re f")
        let data = graphicBoundsData(
            content: "/Panel Do /Legend Do /Unrelated Do\nBT /F1 9 Tf 160 \(legendY + 3) Td (Baseline and new method) Tj ET\nBT /F1 12 Tf 80 \(captionY) Td (Figure 2: Performance comparison.) Tj ET",
            xObjects: [("Panel", panel), ("Legend", legend), ("Unrelated", unrelated)])
        let page = try #require(PDFDocument(data: data)?.page(at: 0))

        let crop = try #require(PDFFigurePreview.crop(number: "2", destination: PDFDestination(page: page, at: CGPoint(x: 80, y: 630))))

        #expect(crop.contains(CGRect(x: 150, y: legendY, width: 260, height: 14)))
        #expect(crop.contains(try textBounds("Baseline and new method", on: page)))
        #expect(!crop.intersects(CGRect(x: 80, y: 700, width: 400, height: 40)))
    }

    @Test
    func anInterveningCaptionSeparatesAnUnrelatedGraphicFromThePanels() throws {
        let panel = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [80 450 480 600]",
                                        content: "80 450 400 150 re f")
        let unrelated = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [100 623 420 637]",
                                            content: "100 623 320 14 re f")
        let data = graphicBoundsData(
            content: "/Panel Do /Unrelated Do\nBT /F1 10 Tf 80 607 Td (Figure 1: Another comparison.) Tj ET\nBT /F1 12 Tf 80 432 Td (Figure 2: Performance comparison.) Tj ET",
            xObjects: [("Panel", panel), ("Unrelated", unrelated)])
        let page = try #require(PDFDocument(data: data)?.page(at: 0))

        let crop = try #require(PDFFigurePreview.crop(number: "2", destination: PDFDestination(page: page, at: CGPoint(x: 80, y: 600))))

        #expect(!crop.intersects(CGRect(x: 100, y: 623, width: 320, height: 14)))
        #expect(!crop.intersects(try textBounds("Figure 1:", on: page)))
    }

    @Test(arguments: [0, 90, 180, 270])
    func rotatedCroppedPagesUseTheSameUnrotatedFigureBounds(rotation: Int) throws {
        let document = try figureDocument(rotation: rotation, cropBox: "[100 100 580 740]")
        let page = try #require(document.page(at: 0))
        let destination = PDFDestination(page: page, at: CGPoint(x: 430, y: 650))
        let unrotated = try figureDocument(cropBox: "[100 100 580 740]")
        let referencePage = try #require(unrotated.page(at: 0))
        let reference = try #require(PDFFigurePreview.crop(number: "2", destination: PDFDestination(page: referencePage, at: CGPoint(x: 430, y: 650))))

        let crop = try #require(PDFFigurePreview.crop(number: "2", destination: destination))

        #expect(crop == reference)
        #expect(crop.minX >= 306)
        #expect(crop.contains(CGRect(x: 310, y: 420, width: 240, height: 230)))
        #expect(page.bounds(for: .cropBox).contains(crop))
    }

    @Test
    func repeatedFigurePreviewsPreserveTheSourcePageGraphics() throws {
        let document = try figureDocument()
        let page = try #require(document.page(at: 0))
        let originalCrop = try #require(page.pageRef).getBoxRect(.cropBox)
        let destination = PDFDestination(page: page, at: CGPoint(x: 430, y: 650))
        let expectedCrop = try #require(PDFFigurePreview.crop(number: "2", destination: destination))

        for _ in 0..<3 {
            let crop = try #require(PDFFigurePreview.crop(number: "2", destination: destination))
            let content = try #require(PDFReferenceContent(document: document, destination: destination,
                                                           crop: crop, fitsEntireCrop: true, title: .figurePreview("2")))
            _ = content.displayPage.thumbnail(of: NSSize(width: 300, height: 300), for: .cropBox)

            #expect(crop == expectedCrop)
            #expect(content.displayPage.bounds(for: .cropBox) == expectedCrop)
            #expect(page.bounds(for: .cropBox) == originalCrop)
            #expect(try #require(page.pageRef).getBoxRect(.cropBox) == originalCrop)
        }
    }

    @Test(arguments: [0, 90, 180, 270], [NSScroller.Style.overlay, .legacy])
    func figurePanelsFitTheWholeCopiedFigureAtDifferentPreviewSizes(rotation: Int, scrollerStyle: NSScroller.Style) throws {
        _ = NSApplication.shared
        let document = try figureDocument(rotation: rotation, cropBox: "[100 100 580 740]")
        let page = try #require(document.page(at: 0))
        let originalCrop = page.bounds(for: .cropBox)
        let destination = PDFDestination(page: page, at: CGPoint(x: 430, y: 650))
        let crop = try #require(PDFFigurePreview.crop(number: "2", destination: destination))
        let content = try #require(PDFReferenceContent(document: document, destination: destination,
                                                       crop: crop, fitsEntireCrop: true, title: .figurePreview("2")))
        let panel = PDFReferencePanel(content: content)
        let scroll = try #require(panel.scrollView)
        scroll.scrollerStyle = scrollerStyle

        #expect(content.displayPage !== page)
        #expect(content.displayPage.bounds(for: .cropBox) == crop)
        #expect(page.bounds(for: .cropBox) == originalCrop)

        for size in [CGSize(width: 620, height: 450), CGSize(width: 300, height: 650),
                     CGSize(width: 650, height: 220)] {
            panel.frame = CGRect(origin: .zero, size: size)
            panel.layoutSubtreeIfNeeded()
            #expect(scroll.scrollerStyle == .overlay)
            let clip = try #require(panel.scrollView).contentView
            let paper = panel.pdfView.convert(crop, from: content.displayPage)
            let viewport = panel.pdfView.convert(clip.bounds, from: clip)

            #expect(panel.pdfView.scaleFactor > 0)
            #expect(paper.minX >= viewport.minX - 0.5 && paper.maxX <= viewport.maxX + 0.5)
            #expect(paper.minY >= viewport.minY - 0.5 && paper.maxY <= viewport.maxY + 0.5)
            #expect(abs(paper.midX - viewport.midX) < 0.5)
            #expect(abs(paper.midY - viewport.midY) < 0.5)
            #expect(abs(min(viewport.width - paper.width, viewport.height - paper.height)) < 0.5)
            #expect(panel.pdfView.document === content.displayDocument)
            #expect(content.displayPage.bounds(for: .cropBox) == crop)
            #expect(page.bounds(for: .cropBox) == originalCrop)

            for (vertical, horizontal) in [(CGFloat(36), CGFloat(0)), (-36, 0), (0, 36), (0, -36)] {
                panel.scroll(by: vertical, horizontal: horizontal)
                let moved = panel.pdfView.convert(crop, from: content.displayPage)
                #expect(abs(moved.minX - paper.minX) < 0.5)
                #expect(abs(moved.minY - paper.minY) < 0.5)
            }

            let panelFrame = panel.frame
            let contentFrame = panel.pdfView.frame
            panel.zoom(by: 2)
            let zoomedViewport = panel.pdfView.convert(clip.bounds, from: clip)
            #expect(panel.frame == panelFrame)
            #expect(panel.pdfView.frame == contentFrame)
            #expect(abs(zoomedViewport.width - viewport.width) < 0.5)
            #expect(abs(zoomedViewport.height - viewport.height) < 0.5)
            for amount in [CGFloat(-10_000), 10_000] {
                let beforeScroll = panel.pdfView.convert(crop, from: content.displayPage)
                panel.scroll(by: amount, horizontal: amount)
                let edge = panel.pdfView.convert(crop, from: content.displayPage)
                if edge.width > viewport.width + 0.5 {
                    // A nearly fitted crop may have less than one point to pan from its center.
                    #expect(abs(edge.minX - beforeScroll.minX) > min(1, (edge.width - viewport.width) / 4))
                    #expect(abs(min(abs(edge.minX - viewport.minX), abs(edge.maxX - viewport.maxX))) < 0.5)
                } else {
                    #expect(abs(edge.midX - viewport.midX) < 0.5)
                }
                if edge.height > viewport.height + 0.5 {
                    #expect(abs(edge.minY - beforeScroll.minY) > min(1, (edge.height - viewport.height) / 4))
                    #expect(abs(min(abs(edge.minY - viewport.minY), abs(edge.maxY - viewport.maxY))) < 0.5)
                } else {
                    #expect(abs(edge.midY - viewport.midY) < 0.5)
                }
                panel.scroll(by: amount, horizontal: amount)
                let repeated = panel.pdfView.convert(crop, from: content.displayPage)
                #expect(abs(repeated.minX - edge.minX) < 0.5)
                #expect(abs(repeated.minY - edge.minY) < 0.5)
            }
            panel.zoom(by: 0.5)
            panel.scroll(by: 36, horizontal: 36)
            let restored = panel.pdfView.convert(crop, from: content.displayPage)
            #expect(abs(restored.minX - paper.minX) < 0.5)
            #expect(abs(restored.minY - paper.minY) < 0.5)
        }
    }

    @Test
    func aCaptionWithoutAnIdentifiableGraphicDoesNotCropArbitraryPageContent() throws {
        let data = graphicBoundsData(
            content: "40 450 200 180 re f\nBT /F1 12 Tf 40 432 Td (Figure 2: Direct page paths.) Tj ET",
            xObjects: [])
        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))

        #expect(PDFFigurePreview.crop(number: "2", destination: PDFDestination(page: page, at: CGPoint(x: 140, y: 630))) == nil)
    }

    @Test
    func aDifferentFigureNumberOrUnrelatedDestinationDoesNotProduceACrop() throws {
        let document = try figureDocument()
        let page = try #require(document.page(at: 0))

        #expect(PDFFigurePreview.crop(number: "20", destination: PDFDestination(page: page, at: CGPoint(x: 430, y: 650))) == nil)
        #expect(PDFFigurePreview.crop(number: "2", destination: PDFDestination(page: page, at: CGPoint(x: 100, y: 200))) == nil)
    }

    private func figureDocument(rotation: Int = 0, cropBox: String = "[0 0 600 800]") throws -> PDFDocument {
        let figure = graphicBoundsStream(dictionary: "/Type /XObject /Subtype /Form /BBox [310 420 550.001 650.00441]",
                                         content: "310 420 240 230 re f")
        let data = graphicBoundsData(
            content: "BT /F1 12 Tf 40 388 Td (The body remains in the left column.) Tj ET\n/Figure Do\nBT /F1 12 Tf 310 402 Td (Figure 2: A vector comparison.) Tj 0 -14 Td (Second caption line.) Tj 0 -34 Td (Body paragraph below the caption.) Tj ET",
            xObjects: [("Figure", figure)], cropBox: cropBox, rotation: rotation)
        return try #require(PDFDocument(data: data))
    }

    private func linkedText(_ text: String, on page: PDFPage) throws -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: try textBounds(text, on: page), forType: .link, withProperties: nil)
        page.addAnnotation(annotation)
        return annotation
    }

    private func textBounds(_ text: String, on page: PDFPage) throws -> CGRect {
        let string = try #require(page.string) as NSString
        let range = string.range(of: text)
        try #require(range.location != NSNotFound)
        return try #require(page.selection(for: range)).bounds(for: page)
    }
}

private let graphicBoundsImage = graphicBoundsStream(
    dictionary: "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode",
    content: "FF0000>")

private func graphicBoundsStream(dictionary: String = "", content: String) -> String {
    "<< \(dictionary) /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream"
}

private func graphicBoundsDocument(content: String, xObjects: [(String, String)],
                                   cropBox: String = "[0 0 600 800]", rotation: Int = 0) throws -> CGPDFDocument {
    let data = graphicBoundsData(content: content, xObjects: xObjects, cropBox: cropBox, rotation: rotation)
    let provider = try #require(CGDataProvider(data: data as CFData))
    return try #require(CGPDFDocument(provider))
}

private func graphicBoundsData(content: String, xObjects: [(String, String)],
                               cropBox: String = "[0 0 600 800]", rotation: Int = 0) -> Data {
    let resources = xObjects.enumerated().map { "/\($0.element.0) \($0.offset + 5) 0 R" }.joined(separator: " ")
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /CropBox \(cropBox) /Rotate \(rotation) /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> /XObject << \(resources) >> >> /Contents 4 0 R >>",
        graphicBoundsStream(content: content)
    ] + xObjects.map(\.1)
    var data = Data("%PDF-1.7\n".utf8)
    var offsets: [Int] = []
    for (index, object) in objects.enumerated() {
        offsets.append(data.count)
        data.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
    }
    let xrefOffset = data.count
    data.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
    for offset in offsets {
        data.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
    }
    data.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
    return data
}
