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
        let height = min(bounds.height - 24, 760)
        return NSRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func cellRect(at position: Int, panelRect: NSRect) -> NSRect {
        if visibleCount == columns {
            return carouselCellRect(at: position, panelRect: panelRect)
        }

        let spacing: CGFloat = 16
        let horizontalInset: CGFloat = 24
        let bottomInset: CGFloat = 24
        let headerHeight: CGFloat = 58
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

    private func carouselCellRect(at position: Int, panelRect: NSRect) -> NSRect {
        let spacing: CGFloat = 18
        let horizontalInset: CGFloat = 22
        let bottomInset: CGFloat = 22
        let headerHeight: CGFloat = 50
        let area = NSRect(
            x: panelRect.minX + horizontalInset,
            y: panelRect.minY + bottomInset,
            width: panelRect.width - horizontalInset * 2,
            height: panelRect.height - headerHeight - bottomInset
        )
        let centerWidth = min(area.width * 0.64, area.height * 1.68)
        let sideWidth = max(96, (area.width - centerWidth - spacing * 2) / 2)
        let sideHeight = area.height * 0.62

        switch position {
        case 0:
            return NSRect(
                x: area.minX,
                y: area.midY - sideHeight / 2,
                width: sideWidth,
                height: sideHeight
            )
        case 1:
            return NSRect(
                x: area.midX - centerWidth / 2,
                y: area.minY,
                width: centerWidth,
                height: area.height
            )
        default:
            return NSRect(
                x: area.maxX - sideWidth,
                y: area.midY - sideHeight / 2,
                width: sideWidth,
                height: sideHeight
            )
        }
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

    private func drawCell(pageIndex: Int, in rect: NSRect) {
        let isSelected = pageIndex == selectedIndex
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        (isSelected ? TokyoNight.selection : TokyoNight.panel).withAlphaComponent(isSelected ? 0.95 : 0.88).setFill()
        path.fill()

        (isSelected ? TokyoNight.blue : TokyoNight.border).withAlphaComponent(isSelected ? 1 : 0.65).setStroke()
        path.lineWidth = isSelected ? 2.4 : 1
        path.stroke()

        let labelHeight: CGFloat = 26
        let imageRect = rect.insetBy(dx: 6, dy: 6)
            .offsetBy(dx: 0, dy: labelHeight / 2)
            .insetBy(dx: 0, dy: labelHeight / 2)

        if let image = thumbnailCache[pageIndex] {
            drawImage(image, in: imageRect)
        }

        drawPageNumber(pageIndex + 1, in: NSRect(x: rect.minX, y: rect.minY + 8, width: rect.width, height: labelHeight))
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
}
