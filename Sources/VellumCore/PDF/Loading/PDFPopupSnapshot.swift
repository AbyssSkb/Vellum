@preconcurrency import PDFKit

struct PDFPopupSnapshot: Sendable {
    let bounds: CGRect
    let isOpen: Bool?

    static func capture(from page: PDFPage) -> [Self] {
        page.annotations.filter { $0.type == "Popup" }.map {
            Self(bounds: $0.bounds, isOpen: ($0.value(forAnnotationKey: .open) as? NSNumber)?.boolValue)
        }
    }

    static func restore(_ snapshots: [Self], to page: PDFPage) -> Bool {
        let popups = page.annotations.filter { $0.type == "Popup" }
        guard popups.count == snapshots.count else { return false }
        // PDFDocument.copy() resets popup fields; update its native objects to retain their parent links.
        for (popup, snapshot) in zip(popups, snapshots) {
            popup.bounds = snapshot.bounds
            if let isOpen = snapshot.isOpen {
                popup.setBoolean(isOpen, forAnnotationKey: .open)
            } else {
                popup.removeValue(forAnnotationKey: .open)
            }
        }
        return true
    }
}
