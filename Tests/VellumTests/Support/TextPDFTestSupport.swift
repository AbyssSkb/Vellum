import AppKit
import PDFKit
import Testing

@MainActor
func makeTextPDF(pages: [[(String, NSPoint)]]) throws -> PDFDocument {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
    let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
    for lines in pages {
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (text, point) in lines {
            (text as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
        }
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
    }
    context.closePDF()
    return try #require(PDFDocument(data: data as Data))
}
