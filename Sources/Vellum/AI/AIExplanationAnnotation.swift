import Foundation
import PDFKit

enum AIExplanationAnnotation {
    static let marker = "Vellum AI Explanation v1"
    private static let legacyMarker = "VimPDF AI Explanation v1"

    static func encode(_ explanation: String) -> String {
        "\(marker)\n\n\(explanation.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    static func decode(_ contents: String?) -> String? {
        guard let contents else { return nil }

        let matchedMarker: String
        if contents.hasPrefix(marker) {
            matchedMarker = marker
        } else if contents.hasPrefix(legacyMarker) {
            matchedMarker = legacyMarker
        } else {
            return nil
        }

        let text = contents
            .dropFirst(matchedMarker.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text)
    }
}

enum HighlightAnnotationMetadata {
    private static let groupKey = PDFAnnotationKey(rawValue: "VellumHighlightGroup")
    private static let legacyGroupKey = PDFAnnotationKey(rawValue: "VimPDFHighlightGroup")

    static func groupID(for annotation: PDFAnnotation) -> String? {
        annotation.value(forAnnotationKey: groupKey) as? String
            ?? annotation.value(forAnnotationKey: legacyGroupKey) as? String
    }

    static func setGroupID(_ groupID: String, for annotation: PDFAnnotation) {
        annotation.setValue(groupID, forAnnotationKey: groupKey)
    }
}
