@preconcurrency import AppKit
import PDFKit

@MainActor
final class PDFReaderContainer: NSView {
    let reader: VellumPDFView

    init(reader: VellumPDFView) {
        self.reader = reader
        super.init(frame: reader.frame)
        reader.autoresizingMask = []
        addSubview(reader)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let readerFrame = bounds
        guard reader.frame != readerFrame else { return }
        let anchor = reader.pendingRestoreAction == nil && !reader.bounds.isEmpty
            ? reader.centerDestination() : nil
        let fitScale = anchor.flatMap { reader.widthFitScale(for: $0.page) }
        let targetScale = reader.animationState.zoomTargetScale ?? reader.scaleFactor
        let fitsWidth = fitScale.map { abs(targetScale - $0) <= max(0.001, $0 * 0.002) } ?? false
        let edge = anchor?.page.flatMap { page -> VellumPDFView.VerticalEdge? in
            guard let scrollView = reader.pdfScrollView else { return nil }
            let originY = scrollView.contentView.bounds.origin.y
            for edge in [VellumPDFView.VerticalEdge.top, .bottom] {
                if let edgeY = reader.pageEdgeOrigin(for: page, edge: edge, in: scrollView),
                   abs(edgeY - originY) < 0.5 { return edge }
            }
            return nil
        }
        if anchor != nil {
            reader.cancelPendingRestore()
            reader.stopScrollAnimation()
            reader.stopZoomState()
        }
        reader.frame = readerFrame
        reader.layoutDocumentView()
        if let anchor, anchor.page?.document === reader.document {
            if fitsWidth { _ = reader.applyWidthFitScaleNow(for: anchor.page) }
            reader.centerBothAxes(on: anchor, pageEdge: edge)
            reader.scheduleReadingPositionReport()
        }
    }
}
