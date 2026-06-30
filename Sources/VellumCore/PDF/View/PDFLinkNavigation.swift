@preconcurrency import PDFKit

enum PDFLinkNavigation {
    static func shouldRecordJumpSource(for annotation: PDFAnnotation?) -> Bool {
        guard let annotation,
              annotation.type == "Link" else { return false }

        if annotation.destination != nil {
            return true
        }

        return annotation.action is PDFActionGoTo
    }
}
