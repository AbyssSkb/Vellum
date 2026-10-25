import CoreGraphics
import Foundation
import Testing
@testable import VellumCore

@Suite("PDF reference native text style")
struct PDFReferenceTextStyleTests {
    @Test
    func onlyTheFirstVisibleRunCanEmphasizeALine() throws {
        let document = try document(content: """
        BT /B 12 Tf 1 0 0 1 40 700 Tm [(Bold) -200 (prefix)] TJ
        /R 12 Tf 1 0 0 1 40 680 Tm (Normal) Tj /B 12 Tf (inline) Tj
        1 0 0 1 200 680 Tm (positioned inline) Tj
        /Unknown 12 Tf 1 0 0 1 40 660 Tm (Unknown) Tj ET
        """)
        #expect(starts(document) == [CGPoint(x: 40, y: 700)])
    }

    @Test
    func relativeLinesAndLeadingRetainTheirOwnFirstRuns() throws {
        let document = try document(content: """
        BT /B 12 Tf 16 TL 40 700 Td (First) Tj 0 -16 TD [(Second)] TJ
        T* (Third) Tj /R 12 Tf T* (Normal) Tj /B 12 Tf 0 -16 Td (Fourth) Tj ET
        """)
        #expect(starts(document) == [700, 684, 668, 636].map { CGPoint(x: 40, y: $0) })
    }

    @Test
    func emptyRunsDoNotConsumeTheStartAndUnknownArrayAdvanceGivesNoEvidence() throws {
        let document = try document(content: """
        BT /B 12 Tf 40 700 Td () Tj [] TJ (Visible) Tj
        0 -20 Td [-200 (Shifted)] TJ 0 -20 Td 16 TL (Quote) ' ET
        """)
        #expect(starts(document) == [CGPoint(x: 40, y: 700), CGPoint(x: 40, y: 644)])
    }

    @Test
    func graphicsStateTransformsAndFontRestorePreservePageCoordinates() throws {
        let document = try document(content: """
        /B 12 Tf q 2 0 0 2 10 20 cm BT 40 300 Td (Scaled) Tj ET
        /R 12 Tf Q BT 40 500 Td (Restored bold) Tj ET
        q 0 1 -1 0 600 0 cm BT /B 12 Tf 40 300 Td (Rotated) Tj ET Q
        """)
        #expect(starts(document) == [CGPoint(x: 90, y: 620), CGPoint(x: 40, y: 500)])
    }

    @Test
    func inheritedResourcesAndDescendantFontMetadataProvideEvidence() throws {
        let document = try document(content: """
        BT /CID 12 Tf 40 700 Td <0001> Tj
        /Weighted 12 Tf 0 -20 Td (Weight) Tj
        /Named 12 Tf 0 -20 Td (Name) Tj ET
        """, extraFonts: """
        /CID << /Type /Font /Subtype /Type0 /BaseFont /Subset /Encoding /Identity-H
          /DescendantFonts [<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Subset
            /FontDescriptor << /Type /FontDescriptor /FontName /ABCDEF+Example-Semibold >> >>] >>
        /Weighted << /Type /Font /Subtype /Type1 /BaseFont /Subset
          /FontDescriptor << /Type /FontDescriptor /FontName /Subset /FontWeight 700 >> >>
        /Named << /Type /Font /Subtype /Type1 /BaseFont /Opaque
          /FontDescriptor << /Type /FontDescriptor /FontName /ABCDEF+Example-Bold >> >>
        """, inherited: true)
        #expect(starts(document) == [700, 680, 660].map { CGPoint(x: 40, y: $0) })
    }

    @Test
    func invisibleAndRaisedTextDoNotClaimTheBodyLineStart() throws {
        let document = try document(content: """
        BT /B 12 Tf 3 Tr 40 700 Td (Invisible) Tj 0 Tr
        0 -20 Td 5 Ts (Raised) Tj 0 Ts 0 -20 Td (Visible) Tj ET
        """)
        #expect(starts(document) == [CGPoint(x: 40, y: 660)])
    }

    @Test
    func unknownGraphicsStateCannotRegainEvidenceThroughAFontChange() throws {
        let document = try document(content: """
        q /Off gs BT /B 12 Tf 40 700 Td (Hidden) Tj ET Q
        BT /B 12 Tf 40 680 Td (Visible after restore) Tj ET
        """, extraResources: "/ExtGState << /Off << /Type /ExtGState /ca 0 /CA 0 >> >>")
        #expect(starts(document) == [CGPoint(x: 40, y: 680)])
    }

    @Test
    func collapsedAndMirroredTextGiveNoEvidenceAndScaleRestoresWithGraphicsState() throws {
        let document = try document(content: """
        q BT /B 12 Tf 0 Tz 40 700 Td (Collapsed bold) Tj
        100 Tz /R 12 Tf 1 0 0 1 40 700 Tm (Ordinary body) Tj ET Q
        q -100 Tz BT /B 12 Tf 40 680 Td (Mirrored) Tj ET Q
        q 0 Tz BT /B 12 Tf 40 660 Td (Collapsed again) Tj ET Q
        BT /B 12 Tf 40 640 Td (Visible after restore) Tj ET
        """)
        #expect(starts(document) == [CGPoint(x: 40, y: 640)])
    }

    private func starts(_ document: CGPDFDocument) -> [CGPoint] {
        PDFReferenceTextStyle.boldLineStarts(on: document.page(at: 1)!)
    }

    private func document(content: String, extraFonts: String = "", extraResources: String = "", inherited: Bool = false) throws -> CGPDFDocument {
        let resources = """
        /Resources << /Font <<
        /R << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
        /B << /Type /Font /Subtype /Type1 /BaseFont /ABCDEF+Helvetica-Bold >>
        \(extraFonts) >> \(extraResources) >>
        """
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 \(inherited ? resources : "") >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] \(inherited ? "" : resources) /Contents 4 0 R >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream"
        ]
        var pdf = "%PDF-1.7\n", offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 \(offsets.count)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF"
        let provider = try #require(CGDataProvider(data: Data(pdf.utf8) as CFData))
        return try #require(CGPDFDocument(provider))
    }
}
