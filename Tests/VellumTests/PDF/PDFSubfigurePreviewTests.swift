@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("PDF subfigure previews")
struct PDFSubfigurePreviewTests {
    @Test(arguments: ["Figure 7(a)", "Figure 7 (a)", "Figures 6 and 7(a)"])
    func explicitPanelIdentityIsRetained(reference: String) throws {
        let fixture = try document(reference: reference)
        let page = try #require(fixture.document.page(at: 0))
        let annotation = try linkedText("7", on: page)

        #expect(PDFFigurePreview.number(for: annotation) == "7(a)")
    }

    @Test(arguments: [false, true])
    func labeledNativePanelsKeepOnlyTheirOwnBodyAndCompleteCaption(stacked: Bool) throws {
        let fixture = try document(stacked: stacked)
        let page = try #require(fixture.document.page(at: 0))
        for (letter, body, other, caption, otherCaption) in [
            ("a", fixture.first, fixture.second, "First panel description continues.", "Second panel description continues."),
            ("b", fixture.second, fixture.first, "Second panel description continues.", "First panel description continues.")
        ] {
            let annotation = try linkedText("7(\(letter))", on: page)
            let destination = PDFDestination(page: page, at: CGPoint(x: body.minX, y: body.maxY))
            guard case let .region(region) = PDFReferencePreview.resolve(for: annotation, destination: destination) else {
                Issue.record("An explicitly labeled subfigure should produce a region")
                continue
            }
            #expect(region.bounds.contains(body))
            #expect(!region.bounds.intersects(other))
            let panelLabel = try #require(PDFReferenceTextLayout.lines(on: page).first { $0.text == "(\(letter))" })
            #expect(region.bounds.contains(panelLabel.bounds))
            let continuation = try #require(region.continuation)
            #expect(continuation.page === page)
            #expect(continuation.bounds.contains(try textBounds(caption, on: page)))
            #expect(!continuation.bounds.intersects(try textBounds(otherCaption, on: page)))

            let content = try #require(PDFReferenceContent(document: fixture.document, destination: destination,
                crop: region.bounds, fitsEntireCrop: true, title: region.title, continuation: region.continuation))
            #expect(content.isValid(in: fixture.document))
            #expect(content.displayDocument.pageCount == 1)
            let visible = try #require(content.displayPage.string)
            #expect(visible.contains(caption))
            #expect(visible.contains(letter == "a" ? "FIRST PANEL CONTENT" : "SECOND PANEL CONTENT"))
            let bounds = content.displayPage.bounds(for: .cropBox)
            let width = Int(ceil(bounds.width)), height = Int(ceil(bounds.height))
            let raster = try #require(CGContext(data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            raster.setFillColor(NSColor.white.cgColor)
            raster.fill(CGRect(x: 0, y: 0, width: width, height: height))
            raster.drawPDFPage(try #require(content.displayPage.pageRef))
            let pixels = try #require(raster.data).assumingMemoryBound(to: UInt8.self)
            var colors = [(red: 0, blue: 0), (red: 0, blue: 0)]
            // PDFKit can extract clipped text; pixels prove both fragments exclude the other panel and its caption.
            for row in 0..<height {
                let fragment = CGFloat(height - row - 1) < continuation.bounds.height ? 0 : 1
                for x in 0..<width {
                    let offset = row * raster.bytesPerRow + x * 4
                    if pixels[offset] > 160 && pixels[offset + 1] < 80 && pixels[offset + 2] < 80 {
                        colors[fragment].red += 1
                    }
                    if pixels[offset + 2] > 160 && pixels[offset] < 80 && pixels[offset + 1] < 80 {
                        colors[fragment].blue += 1
                    }
                }
            }
            for fragment in colors {
                #expect(letter == "a" ? fragment.red > 0 && fragment.blue == 0 : fragment.blue > 0 && fragment.red == 0)
            }
        }
    }

    @Test(arguments: ["singleGraphic", "missingLabel", "missingCaption", "duplicateLabel", "sharedLegendText", "sharedLegendGraphic"])
    func ambiguousPanelOwnershipRetainsTheWholeFigure(ambiguity: String) throws {
        let fixture = try document(ambiguity: ambiguity)
        let page = try #require(fixture.document.page(at: 0))
        let annotation = try linkedText("7(a)", on: page)
        let destination = PDFDestination(page: page, at: CGPoint(x: 50, y: 650))
        let expected = try #require(PDFFigurePreview.crop(number: "7", destination: destination))

        guard case let .region(region) = PDFReferencePreview.resolve(for: annotation, destination: destination) else {
            Issue.record("Uncertain subfigure ownership should retain the useful whole figure")
            return
        }
        #expect(region.bounds == expected)
        #expect(region.continuation == nil)
        #expect(region.bounds.contains(fixture.first))
        #expect(region.bounds.contains(fixture.second))
    }

    @Test
    func anUnqualifiedFigureReferenceKeepsTheExistingCompleteCrop() throws {
        let fixture = try document(reference: "Figure 7")
        let page = try #require(fixture.document.page(at: 0))
        let annotation = try linkedText("7", on: page)
        let destination = PDFDestination(page: page, at: CGPoint(x: 50, y: 650))
        let expected = try #require(PDFFigurePreview.crop(number: "7", destination: destination))

        guard case let .region(region) = PDFReferencePreview.resolve(for: annotation, destination: destination) else {
            Issue.record("The ordinary figure should remain a complete crop")
            return
        }
        #expect(PDFFigurePreview.number(for: annotation) == "7")
        #expect(region.bounds == expected)
        #expect(region.continuation == nil)
    }

    private func document(reference: String = "Figure 7(a) and Figure 7(b)", stacked: Bool = false,
                          ambiguity: String = "") throws -> (document: PDFDocument, first: CGRect, second: CGRect) {
        let first = stacked ? CGRect(x: 40, y: 470, width: 480, height: 180)
            : CGRect(x: 40, y: 450, width: 190, height: 200)
        let second = stacked ? CGRect(x: 40, y: 230, width: 480, height: 180)
            : CGRect(x: 270, y: 450, width: 290, height: 200)
        let wrapper = first.union(second)
        func label(_ text: String, x: CGFloat, y: CGFloat) -> String {
            let color = text.contains("First panel") ? "1 0 0 rg" : text.contains("Second panel") ? "0 0 1 rg" : "0 g"
            return "q \(color) BT /F1 12 Tf 1 0 0 1 \(x) \(y) Tm (\(escaped(text))) Tj ET Q"
        }
        func form(_ bounds: CGRect, text: String) -> String {
            let color = text == "FIRST PANEL CONTENT" ? "1 0 0 rg" : text == "SECOND PANEL CONTENT" ? "0 0 1 rg" : "0.9 g"
            return stream("q \(color) \(bounds.minX) \(bounds.minY) \(bounds.width) \(bounds.height) re f Q\n"
                + label(text, x: bounds.minX + 8, y: bounds.midY),
                dictionary: "/Type /XObject /Subtype /Form /BBox [\(bounds.minX) \(bounds.minY) \(bounds.maxX) \(bounds.maxY)]")
        }
        let captionY: CGFloat = stacked ? 190 : 410
        let firstCaption = ambiguity == "missingCaption" ? "Figure 7: Both panels share this description."
            : "Figure 7: (a) First panel description."
        var content = label("See \(reference) for details.", x: 40, y: 730) + "\n/Wrapper Do\n"
        content += label("(a)", x: first.midX - 6, y: first.minY - 18) + "\n"
        if ambiguity != "missingLabel" {
            content += label("(b)", x: second.midX - 6, y: second.minY - 18) + "\n"
        }
        if ambiguity == "duplicateLabel" {
            content += label("(a)", x: second.midX + 20, y: second.minY - 18) + "\n"
        }
        if ambiguity == "sharedLegendText" {
            content += "BT /F1 8 Tf 1 0 0 1 236 540 Tm (units) Tj ET\n"
        }
        if ambiguity == "sharedLegendGraphic" { content += "/Legend Do\n" }
        content += label(firstCaption, x: 40, y: captionY) + "\n"
        if ambiguity != "missingCaption" {
            content += label("First panel description continues.", x: 40, y: captionY - 14) + "\n"
            content += label("(b) Second panel description.", x: 40, y: captionY - 28) + "\n"
            content += label("Second panel description continues.", x: 40, y: captionY - 42) + "\n"
        }
        content += label("Unrelated body paragraph below the figure.", x: 40, y: captionY - 80)
        let wrapperContent = ambiguity == "singleGraphic"
            ? label("FIRST PANEL CONTENT", x: first.minX + 8, y: first.midY) + "\n"
                + label("SECOND PANEL CONTENT", x: second.minX + 8, y: second.midY)
            : "/First Do /Second Do"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> /XObject << /First 5 0 R /Second 6 0 R /Wrapper 7 0 R /Legend 8 0 R >> >> /Contents 4 0 R >>",
            stream(content), form(first, text: "FIRST PANEL CONTENT"), form(second, text: "SECOND PANEL CONTENT"),
            stream(wrapperContent, dictionary: "/Type /XObject /Subtype /Form /BBox [\(wrapper.minX) \(wrapper.minY) \(wrapper.maxX) \(wrapper.maxY)]"),
            form(CGRect(x: 242, y: 510, width: 12, height: 8), text: "")
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
        return (try #require(PDFDocument(data: data)), first, second)
    }

    private func stream(_ content: String, dictionary: String = "") -> String {
        "<< \(dictionary) /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream"
    }

    private func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
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
