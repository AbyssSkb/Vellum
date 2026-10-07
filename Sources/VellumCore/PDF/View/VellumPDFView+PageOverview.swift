@preconcurrency import AppKit
import PDFKit

extension VellumPDFView {
    private static let pageOverviewColumns = 3

    func beginPageOverview() -> Bool {
        guard let document, document.pageCount > 0 else { return false }

        stopScrollAnimation()
        stopZoomState()
        hideAIExplanationPopover()

        let pageIndex = currentVisiblePageIndex(in: document)
        let overlay = PageOverviewOverlayView(
            document: document,
            selectedIndex: pageIndex,
            columns: Self.pageOverviewColumns
        )
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]

        pageOverviewController?.dismiss()
        addSubview(overlay)
        pageOverviewController = PageOverviewController(
            overlay: overlay,
            originalIndex: pageIndex,
            selectedIndex: pageIndex,
            pageCount: document.pageCount,
            columns: Self.pageOverviewColumns
        )
        return true
    }

    func movePageOverview(_ navigation: PageOverviewNavigation) -> Bool {
        guard let pageOverviewController else { return false }
        pageOverviewController.move(navigation)
        return true
    }

    func finishPageOverview() {
        guard let pageOverviewController else { return }
        let selectedIndex = pageOverviewController.selectedIndex
        let originalIndex = pageOverviewController.originalIndex

        pageOverviewController.dismiss()
        self.pageOverviewController = nil

        guard selectedIndex != originalIndex else { return }

        vimGoToPage(selectedIndex + 1)
    }

    func cancelPageOverview() {
        pageOverviewController?.dismiss()
        pageOverviewController = nil
    }

    private func currentVisiblePageIndex(in document: PDFDocument) -> Int {
        if let snapshot = snapshot() {
            return min(max(snapshot.pageIndex, 0), document.pageCount - 1)
        }

        if let page = currentPage {
            let index = document.index(for: page)
            if index != NSNotFound {
                return min(max(index, 0), document.pageCount - 1)
            }
        }

        return 0
    }
}

@MainActor
final class PageOverviewController {
    let overlay: PageOverviewOverlayView
    let originalIndex: Int
    private(set) var selectedIndex: Int

    private let pageCount: Int
    private let columns: Int

    init(
        overlay: PageOverviewOverlayView,
        originalIndex: Int,
        selectedIndex: Int,
        pageCount: Int,
        columns: Int
    ) {
        self.overlay = overlay
        self.originalIndex = originalIndex
        self.selectedIndex = selectedIndex
        self.pageCount = pageCount
        self.columns = columns
    }

    func move(_ navigation: PageOverviewNavigation) {
        let delta: Int
        switch navigation {
        case .previous:
            delta = -1
        case .next:
            delta = 1
        case .previousRow:
            delta = -columns
        case .nextRow:
            delta = columns
        }

        let nextIndex = min(max(selectedIndex + delta, 0), pageCount - 1)
        guard nextIndex != selectedIndex else { return }

        selectedIndex = nextIndex
        overlay.update(selectedIndex: selectedIndex)
    }

    func dismiss() {
        overlay.dismiss()
    }
}

@MainActor
final class PageOverviewOverlayView: NSView {
    private let document: PDFDocument
    private let columns: Int
    private let visibleCount: Int
    private var selectedIndex: Int
    private var visibleSlots: [Int?] = []
    private let thumbnails = PageOverviewThumbnailLoader()

    init(document: PDFDocument, selectedIndex: Int, columns: Int) {
        self.document = document
        self.selectedIndex = selectedIndex
        self.columns = columns
        self.visibleCount = columns
        super.init(frame: .zero)
        wantsLayer = true
        alphaValue = 0
        updateVisibleSlots()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.11
            animator().alphaValue = 1
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(selectedIndex: Int) {
        self.selectedIndex = selectedIndex
        updateVisibleSlots()
        needsDisplay = true
    }

    func dismiss() {
        thumbnails.cancel()
        removeFromSuperview()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateThumbnails()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateThumbnails()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateThumbnails()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        TokyoNight.backgroundDeep.withAlphaComponent(0.90).setFill()
        bounds.fill()

        let panelRect = gridPanelRect()
        let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: 8, yRadius: 8)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        TokyoNight.panelElevated.setFill()
        panelPath.fill()
        NSGraphicsContext.restoreGraphicsState()
        TokyoNight.foreground.withAlphaComponent(0.14).setStroke()
        panelPath.lineWidth = 0.5
        panelPath.stroke()

        drawHeader(in: panelRect)

        for (position, pageIndex) in visibleSlots.enumerated() {
            guard let pageIndex else { continue }
            drawCell(pageIndex: pageIndex, in: cellRect(at: position, panelRect: panelRect))
        }
    }

    private func updateVisibleSlots() {
        guard document.pageCount > 0 else {
            visibleSlots = []
            return
        }

        visibleSlots = PageOverviewWindow.slots(
            selectedIndex: selectedIndex,
            pageCount: document.pageCount,
            visibleCount: visibleCount
        )
        updateThumbnails()
    }

    private func updateThumbnails() {
        guard let window, bounds.width > 24, bounds.height > 24 else { return }
        let slotRect = cellRect(at: 0, panelRect: gridPanelRect())
        let scale = window.backingScaleFactor
        thumbnails.update(
            document: document,
            pageIndexes: visibleSlots.compactMap(\.self),
            selectedIndex: selectedIndex,
            maximumPixelSize: NSSize(
                width: max(1, (slotRect.width - 12) * scale),
                height: max(1, (slotRect.height - 38) * scale)
            )
        ) { [weak self] in
            self?.needsDisplay = true
        }
    }

    private func gridPanelRect() -> NSRect {
        let width = max(1, min(bounds.width - 48, 980))
        let height = max(1, min(bounds.height - 48, fittedPanelHeight(for: width)))
        return NSRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func fittedPanelHeight(for width: CGFloat) -> CGFloat {
        let spacing: CGFloat = 18
        let horizontalInset: CGFloat = 20
        let bottomInset: CGFloat = 16
        let headerHeight: CGFloat = 44
        let labelHeight: CGFloat = 26
        let padding: CGFloat = 6
        let gridWidth = width - horizontalInset * 2
        let cellWidth = (gridWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let imageHeight = (cellWidth - padding * 2) / pageAspectRatio(for: selectedIndex)
        let cardHeight = imageHeight + labelHeight + padding * 2
        return headerHeight + bottomInset + cardHeight
    }

    private func cellRect(at position: Int, panelRect: NSRect) -> NSRect {
        let spacing: CGFloat = 18
        let horizontalInset: CGFloat = 20
        let bottomInset: CGFloat = 16
        let headerHeight: CGFloat = 44
        let rows = max(1, Int(ceil(Double(visibleCount) / Double(columns))))
        let gridWidth = panelRect.width - horizontalInset * 2
        let gridHeight = panelRect.height - headerHeight - bottomInset
        let cellWidth = (gridWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let cellHeight = (gridHeight - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        let column = position % columns
        let row = position / columns
        let y = panelRect.maxY - headerHeight - CGFloat(row + 1) * cellHeight - CGFloat(row) * spacing

        return NSRect(
            x: panelRect.minX + horizontalInset + CGFloat(column) * (cellWidth + spacing),
            y: y,
            width: cellWidth,
            height: cellHeight
        )
    }

    private func drawHeader(in panelRect: NSRect) {
        let title = AppUILanguage.saved().text(.pageOverviewPosition(selectedIndex + 1, document.pageCount))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: TokyoNight.muted
        ]
        title.draw(
            at: NSPoint(x: panelRect.minX + 26, y: panelRect.maxY - 28),
            withAttributes: attributes
        )
        let divider = NSBezierPath()
        divider.move(to: NSPoint(x: panelRect.minX + 20, y: panelRect.maxY - 38))
        divider.line(to: NSPoint(x: panelRect.maxX - 20, y: panelRect.maxY - 38))
        divider.lineWidth = 0.5
        TokyoNight.foreground.withAlphaComponent(0.07).setStroke()
        divider.stroke()
    }

    private func drawCell(pageIndex: Int, in slotRect: NSRect) {
        let rect = fittedCellRect(for: pageIndex, in: slotRect)
        let isSelected = pageIndex == selectedIndex
        let labelHeight: CGFloat = 26
        let imageRect = NSRect(
            x: rect.minX + 6,
            y: rect.minY + labelHeight + 6,
            width: rect.width - 12,
            height: rect.height - labelHeight - 12
        )

        let paper = NSBezierPath(roundedRect: imageRect, xRadius: 3, yRadius: 3)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(isSelected ? 0.34 : 0.20)
        shadow.shadowBlurRadius = isSelected ? 14 : 8
        shadow.shadowOffset = NSSize(width: 0, height: isSelected ? -5 : -3)
        shadow.set()
        NSColor.white.setFill()
        paper.fill()
        NSGraphicsContext.restoreGraphicsState()

        if isSelected {
            let outline = NSBezierPath(roundedRect: imageRect.insetBy(dx: -3, dy: -3), xRadius: 5, yRadius: 5)
            TokyoNight.blue.withAlphaComponent(0.95).setStroke()
            outline.lineWidth = 1.5
            outline.stroke()
        }

        if let image = thumbnails.images[pageIndex] {
            drawImage(image, in: imageRect)
        }

        drawPageNumber(pageIndex + 1, selected: isSelected,
                       in: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: labelHeight))
    }

    private func fittedCellRect(for pageIndex: Int, in slotRect: NSRect) -> NSRect {
        let labelHeight: CGFloat = 26
        let padding: CGFloat = 6
        let aspectRatio = pageAspectRatio(for: pageIndex)
        let previewScale: CGFloat = pageIndex == selectedIndex ? 1 : 0.96
        let maxImageWidth = max(1, slotRect.width - padding * 2) * previewScale
        let maxImageHeight = max(1, slotRect.height - labelHeight - padding * 2) * previewScale

        var imageWidth = maxImageWidth
        var imageHeight = imageWidth / aspectRatio
        if imageHeight > maxImageHeight {
            imageHeight = maxImageHeight
            imageWidth = imageHeight * aspectRatio
        }

        let cardWidth = imageWidth + padding * 2
        let cardHeight = imageHeight + labelHeight + padding * 2
        return NSRect(
            x: slotRect.midX - cardWidth / 2,
            y: slotRect.minY,
            width: cardWidth,
            height: cardHeight
        )
    }

    private func drawImage(_ image: NSImage, in rect: NSRect) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let fittedSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let fittedRect = NSRect(
            x: rect.midX - fittedSize.width / 2,
            y: rect.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: fittedRect, xRadius: 3, yRadius: 3).addClip()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: fittedRect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawPageNumber(_ pageNumber: Int, selected: Bool, in rect: NSRect) {
        let text = "\(pageNumber)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: selected ? .semibold : .regular),
            .foregroundColor: selected ? TokyoNight.foreground : TokyoNight.muted
        ]
        let size = text.size(withAttributes: attributes)
        if selected {
            let badge = NSRect(x: rect.midX - max(32, size.width + 18) / 2,
                               y: rect.midY - 10, width: max(32, size.width + 18), height: 20)
            TokyoNight.blue.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 5, yRadius: 5).fill()
        }
        text.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func pageAspectRatio(for index: Int) -> CGFloat {
        guard let page = document.page(at: index) else { return 16 / 9 }
        let bounds = PDFPageDisplayGeometry(page: page, box: .cropBox).bounds
        guard bounds.width > 0, bounds.height > 0 else { return 16 / 9 }
        return bounds.width / bounds.height
    }
}
