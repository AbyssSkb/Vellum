import PDFKit

struct PDFPageDisplayGeometry {
    // Coordinates start at the displayed crop box's bottom-left, with y increasing upward.
    let bounds: CGRect
    private let pageToDisplay: CGAffineTransform

    init(page: PDFPage, box: PDFDisplayBox) {
        let crop = page.bounds(for: box)
        let rotation = ((page.rotation % 360) + 360) % 360
        switch rotation {
        case 90:
            pageToDisplay = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: -crop.minY, ty: crop.maxX)
        case 180:
            pageToDisplay = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: crop.maxX, ty: crop.maxY)
        case 270:
            pageToDisplay = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: crop.maxY, ty: -crop.minX)
        default:
            pageToDisplay = CGAffineTransform(translationX: -crop.minX, y: -crop.minY)
        }
        bounds = CGRect(origin: .zero, size: rotation == 90 || rotation == 270
            ? CGSize(width: crop.height, height: crop.width) : crop.size)
    }

    func point(forPagePoint point: CGPoint) -> CGPoint {
        point.applying(pageToDisplay)
    }

    func pagePoint(forDisplayPoint point: CGPoint) -> CGPoint {
        point.applying(pageToDisplay.inverted())
    }

    func rect(forPageRect rect: CGRect) -> CGRect {
        rect.applying(pageToDisplay)
    }

    func pageRect(forDisplayRect rect: CGRect) -> CGRect {
        rect.applying(pageToDisplay.inverted())
    }
}
