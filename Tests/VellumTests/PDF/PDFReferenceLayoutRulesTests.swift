import CoreGraphics
import Foundation
import Testing
@testable import VellumCore

@Suite("PDF reference layout rules")
struct PDFReferenceLayoutRulesTests {
    @Test
    func directRulesAreSeparateFromFigureRegionsAndIgnoreUnpaintedOrThickPaths() throws {
        let document = try rulesDocument(content: """
            40 700 m 260 700 l S 40 700 m 260 700 l S
            40 600 220 1 re f 40 550 m 40 650 l S
            100 100 m 105 100 l S 100 200 m 150 201 l S
            40 300 220 30 re f 40 400 m 260 400 l f
            40 450 m 260 450 l n
            """)
        let page = try #require(document.page(at: 1))

        #expect(PDFGraphicBounds.layoutRules(on: page) == [
            CGRect(x: 40, y: 699.75, width: 220, height: 0.5),
            CGRect(x: 40, y: 600, width: 220, height: 1),
            CGRect(x: 39.75, y: 550, width: 0.5, height: 100)
        ])
        #expect(PDFGraphicBounds.regions(on: page).isEmpty)
    }

    @Test
    func transformsRestoreAndNestedFormsComposeTheirMatrices() throws {
        let content = "10 40 m 110 40 l S"
        let form = """
            << /Type /XObject /Subtype /Form /BBox [0 0 300 200] /Matrix [1 0 0 1 10 20] /Length \(content.utf8.count) >>
            stream
            \(content)
            endstream
            """
        let document = try rulesDocument(content: """
            q 2 0 0 3 40 50 cm /Rule Do Q
            300 400 m 400 400 l S
            q 0 1 -1 0 400 100 cm 10 40 m 110 40 l S Q
            """, form: form)
        let page = try #require(document.page(at: 1))

        #expect(PDFGraphicBounds.layoutRules(on: page) == [
            CGRect(x: 80, y: 229.75, width: 200, height: 0.5),
            CGRect(x: 300, y: 399.75, width: 100, height: 0.5),
            CGRect(x: 359.75, y: 110, width: 0.5, height: 100)
        ])
    }

    @Test(arguments: [0, 90, 180, 270])
    func rectangularClipsAndCropUseUnrotatedPageCoordinates(rotation: Int) throws {
        let document = try rulesDocument(content: """
            q 150 150 300 300 re W n
            50 200 m 550 200 l S 200 50 m 200 750 l S Q
            50 650 m 550 650 l S
            """, rotation: rotation, crop: "[100 100 500 700]")
        let page = try #require(document.page(at: 1))

        #expect(PDFGraphicBounds.layoutRules(on: page) == [
            CGRect(x: 150, y: 199.75, width: 300, height: 0.5),
            CGRect(x: 199.75, y: 150, width: 0.5, height: 300),
            CGRect(x: 100, y: 649.75, width: 400, height: 0.5)
        ])
        #expect(PDFGraphicBounds.regions(on: page).isEmpty)
    }

    @Test
    func unknownClipsDiscardTheirFormRulesAndRestoreAfterQ() throws {
        let content = "40 600 m 260 600 l S q 0 0 m 300 0 l 150 500 l h W n 40 400 m 260 400 l S Q"
        let form = "<< /Type /XObject /Subtype /Form /BBox [0 0 300 700] /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream"
        let document = try rulesDocument(content: "/Rule Do 320 500 m 560 500 l S", form: form)
        let page = try #require(document.page(at: 1))

        #expect(PDFGraphicBounds.layoutRules(on: page) == [CGRect(x: 320, y: 499.75, width: 240, height: 0.5)])
    }
}

private func rulesDocument(content: String, form: String? = nil,
                           rotation: Int = 0, crop: String = "[0 0 600 800]") throws -> CGPDFDocument {
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /CropBox \(crop) /Rotate \(rotation) /Resources << /XObject << \(form == nil ? "" : "/Rule 5 0 R") >> >> /Contents 4 0 R >>",
        "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream"
    ] + (form.map { [$0] } ?? [])
    var data = Data("%PDF-1.7\n".utf8)
    var offsets: [Int] = []
    for (index, object) in objects.enumerated() {
        offsets.append(data.count)
        data.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
    }
    let xref = data.count
    data.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
    for offset in offsets { data.append(Data(String(format: "%010d 00000 n \n", offset).utf8)) }
    data.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
    let provider = try #require(CGDataProvider(data: data as CFData))
    return try #require(CGPDFDocument(provider))
}
