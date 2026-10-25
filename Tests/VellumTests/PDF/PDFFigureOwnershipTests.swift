@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF figure caption ownership")
struct PDFFigureOwnershipTests {
    @Test
    func aBodyMentionBesideTheGraphicCannotReplaceItsCaption() throws {
        let document = try fixture(content: """
            /Figure Do
            BT /F1 12 Tf 60 432 Td (As shown in Figure 2, the panels agree.) Tj ET
            BT /F1 12 Tf 60 408 Td (Figure 2: Complete comparison.) Tj 0 -14 Td (The caption continues here.) Tj ET
            BT /F1 12 Tf 60 350 Td (Unrelated body after the caption.) Tj ET
            """, graphic: CGRect(x: 60, y: 452, width: 440, height: 198))
        let page = try #require(document.page(at: 0))
        let crop = try #require(PDFFigurePreview.crop(number: "2", destination:
            PDFDestination(page: page, at: CGPoint(x: 60, y: 650))))

        #expect(crop.contains(try bounds("Figure 2: Complete comparison.", page: page)))
        #expect(crop.contains(try bounds("The caption continues here.", page: page)))
        #expect(!crop.intersects(try bounds("Unrelated body after the caption.", page: page)))
    }

    @Test
    func aCaptionCanStartAfterWhitespaceWithoutAcceptingAnInlineMention() throws {
        let document = try fixture(content: """
            /Figure Do
            BT /F1 12 Tf 60 432 Td (The earlier Figure 2 mention is body text.) Tj ET
            BT /F1 12 Tf 60 408 Td (   Figure 2: Complete comparison.) Tj ET
            """, graphic: CGRect(x: 60, y: 452, width: 440, height: 198))
        let page = try #require(document.page(at: 0))
        let crop = try #require(PDFFigurePreview.crop(number: "2", destination:
            PDFDestination(page: page, at: CGPoint(x: 60, y: 650))))

        #expect(crop.contains(try bounds("Figure 2: Complete comparison.", page: page)))
    }

    @Test
    func tallBodyRowsCannotBridgeTheWhitespaceBelowACaption() throws {
        let document = try fixture(content: """
            /Figure Do
            BT /F1 12 Tf 60 432 Td (Figure 2: A complete comparison.) Tj 0 -14 Td (The final caption line stays visible.) Tj ET
            BT /F1 12 Tf 60 389 Td (Unrelated prose in the first column.) Tj ET
            BT /F1 12 Tf 310 394 Td (Raised formula fragment.) Tj ET
            BT /F1 12 Tf 60 375 Td (More unrelated prose follows.) Tj ET
            """, graphic: CGRect(x: 60, y: 452, width: 440, height: 198))
        let page = try #require(document.page(at: 0))
        let crop = try #require(PDFFigurePreview.crop(number: "2", destination:
            PDFDestination(page: page, at: CGPoint(x: 60, y: 650))))

        #expect(crop.contains(try bounds("The final caption line stays visible.", page: page)))
        #expect(!crop.intersects(try bounds("Unrelated prose in the first column.", page: page)))
        #expect(!crop.intersects(try bounds("Raised formula fragment.", page: page)))
        #expect(!crop.intersects(try bounds("More unrelated prose follows.", page: page)))
    }

    private func bounds(_ text: String, page: PDFPage) throws -> CGRect {
        let string = try #require(page.string) as NSString
        let range = string.range(of: text)
        try #require(range.location != NSNotFound)
        return try #require(page.selection(for: range)).bounds(for: page)
    }

    private func fixture(content: String, graphic: CGRect) throws -> PDFDocument {
        func stream(_ source: String, dictionary: String = "") -> String {
            "<< \(dictionary) /Length \(source.utf8.count) >>\nstream\n\(source)\nendstream"
        }
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> /XObject << /Figure 5 0 R >> >> /Contents 4 0 R >>",
            stream(content),
            stream("\(graphic.minX) \(graphic.minY) \(graphic.width) \(graphic.height) re f",
                dictionary: "/Type /XObject /Subtype /Form /BBox [\(graphic.minX) \(graphic.minY) \(graphic.maxX) \(graphic.maxY)]")
        ]
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
        return try #require(PDFDocument(data: data))
    }
}
