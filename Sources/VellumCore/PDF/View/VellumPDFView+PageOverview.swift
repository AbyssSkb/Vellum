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

        guard selectedIndex != originalIndex else {
            focus()
            return
        }

        vimGoToPage(selectedIndex + 1)
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
        overlay.removeFromSuperview()
    }
}

@MainActor
final class PageOverviewOverlayView: NSView {
    private let document: PDFDocument
    private let columns: Int
    private let visibleCount: Int
    private var selectedIndex: Int
    private var visibleSlots: [Int?] = []
    private var thumbnailCache: [Int: NSImage] = [:]

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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.58).setFill()
        bounds.fill()

        let panelRect = gridPanelRect()
        let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: 10, yRadius: 10)
        TokyoNight.backgroundDeep.withAlphaComponent(0.92).setFill()
        panelPath.fill()
        TokyoNight.border.withAlphaComponent(0.72).setStroke()
        panelPath.lineWidth = 1
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

        for index in visibleSlots.compactMap(\.self) where thumbnailCache[index] == nil {
            thumbnailCache[index] = thumbnail(for: index)
        }
    }

    private func gridPanelRect() -> NSRect {
        let width = min(bounds.width - 24, 1800)
        let height = min(bounds.height - 24, fittedPanelHeight(for: width))
        return NSRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func fittedPanelHeight(for width: CGFloat) -> CGFloat {
        let spacing: CGFloat = 12
        let horizontalInset: CGFloat = 16
        let bottomInset: CGFloat = 16
        let headerHeight: CGFloat = 46
        let labelHeight: CGFloat = 26
        let padding: CGFloat = 6
        let gridWidth = width - horizontalInset * 2
        let cellWidth = (gridWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let imageHeight = (cellWidth - padding * 2) / pageAspectRatio(for: selectedIndex)
        let cardHeight = imageHeight + labelHeight + padding * 2
        return headerHeight + bottomInset + cardHeight
    }

    private func cellRect(at position: Int, panelRect: NSRect) -> NSRect {
        let spacing: CGFloat = 12
        let horizontalInset: CGFloat = 16
        let bottomInset: CGFloat = 16
        let headerHeight: CGFloat = 46
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
        let title = "Page \(selectedIndex + 1) of \(document.pageCount)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: TokyoNight.foreground
        ]
        title.draw(
            at: NSPoint(x: panelRect.minX + 22, y: panelRect.maxY - 34),
            withAttributes: attributes
        )
    }

    private func drawCell(pageIndex: Int, in slotRect: NSRect) {
        let rect = fittedCellRect(for: pageIndex, in: slotRect)
        let isSelected = pageIndex == selectedIndex
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        (isSelected ? TokyoNight.selection : TokyoNight.panel).withAlphaComponent(isSelected ? 0.95 : 0.88).setFill()
        path.fill()

        (isSelected ? TokyoNight.blue : TokyoNight.border).withAlphaComponent(isSelected ? 1 : 0.65).setStroke()
        path.lineWidth = isSelected ? 2.4 : 1
        path.stroke()

        let labelHeight: CGFloat = 26
        let imageRect = NSRect(
            x: rect.minX + 6,
            y: rect.minY + labelHeight + 6,
            width: rect.width - 12,
            height: rect.height - labelHeight - 12
        )

        if let image = thumbnailCache[pageIndex] {
            drawImage(image, in: imageRect)
        }

        drawPageNumber(pageIndex + 1, in: NSRect(x: rect.minX, y: rect.minY + 8, width: rect.width, height: labelHeight))
    }

    private func fittedCellRect(for pageIndex: Int, in slotRect: NSRect) -> NSRect {
        let labelHeight: CGFloat = 26
        let padding: CGFloat = 6
        let aspectRatio = pageAspectRatio(for: pageIndex)
        let maxImageWidth = max(1, slotRect.width - padding * 2)
        let maxImageHeight = max(1, slotRect.height - labelHeight - padding * 2)

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
            y: slotRect.midY - cardHeight / 2,
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

        NSColor.white.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: fittedRect.insetBy(dx: -1, dy: -1), xRadius: 4, yRadius: 4).fill()
        image.draw(in: fittedRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func drawPageNumber(_ pageNumber: Int, in rect: NSRect) {
        let text = "\(pageNumber)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: TokyoNight.foreground
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.minY + 5),
            withAttributes: attributes
        )
    }

    private func thumbnail(for index: Int) -> NSImage? {
        guard let page = document.page(at: index) else { return nil }
        return page.thumbnail(of: NSSize(width: 960, height: 630), for: .cropBox)
    }

    private func pageAspectRatio(for index: Int) -> CGFloat {
        guard let page = document.page(at: index) else { return 16 / 9 }
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 0, bounds.height > 0 else { return 16 / 9 }
        return bounds.width / bounds.height
    }
}
