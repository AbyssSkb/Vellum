import Foundation
import PDFKit

enum AIExplanationAnnotation {
    static let marker = "VimPDF AI Explanation v1"

    static func encode(_ explanation: String) -> String {
        "\(marker)\n\n\(explanation.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    static func decode(_ contents: String?) -> String? {
        guard let contents,
              contents.hasPrefix(marker) else { return nil }

        let text = contents
            .dropFirst(marker.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text)
    }
}

enum HighlightAnnotationMetadata {
    private static let groupKey = PDFAnnotationKey(rawValue: "VimPDFHighlightGroup")

    static func groupID(for annotation: PDFAnnotation) -> String? {
        annotation.value(forAnnotationKey: groupKey) as? String
    }

    static func setGroupID(_ groupID: String, for annotation: PDFAnnotation) {
        annotation.setValue(groupID, forAnnotationKey: groupKey)
    }
}
