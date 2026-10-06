@preconcurrency import AppKit

final class TokyoNightOutlineRowView: NSTableRowView {
    private static let horizontalInset: CGFloat = 10
    var contentIndent: CGFloat = 0
    var isBranch = false
    private var mouseInside = false {
        didSet { needsDisplay = true }
    }
    private var hoverTrackingArea: NSTrackingArea?

    override var isSelected: Bool {
        didSet { updateTextAppearance() }
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        updateTextAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
            self.hoverTrackingArea = nil
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        mouseInside = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        mouseInside = false
    }

    override func drawBackground(in dirtyRect: NSRect) {
        if mouseInside && !isSelected {
            let hoverRect = roundedBackgroundRect()
            let path = NSBezierPath(roundedRect: hoverRect, xRadius: 5, yRadius: 5)
            TokyoNight.panelElevated.withAlphaComponent(0.35).setFill()
            path.fill()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }

        let selectionRect = roundedBackgroundRect()
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: 5, yRadius: 5)
        TokyoNight.selection.withAlphaComponent(0.5).setFill()
        path.fill()
        TokyoNight.foreground.withAlphaComponent(isEmphasized ? 0.06 : 0.03).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        TokyoNight.blue.withAlphaComponent(isEmphasized ? 0.9 : 0.6).setFill()
        NSBezierPath(roundedRect: NSRect(x: selectionRect.minX + 4, y: selectionRect.midY - 6,
                                       width: 2, height: 12), xRadius: 1, yRadius: 1).fill()
    }

    private func updateTextAppearance() {
        for case let cell as NSTableCellView in subviews {
            cell.textField?.font = .systemFont(ofSize: 13, weight: isSelected ? .medium : .regular)
            cell.textField?.textColor = isSelected ? TokyoNight.foreground : TokyoNight.muted
            (cell as? PDFOutlineCellView)?.pageNumberField.textColor = isSelected
                ? TokyoNight.foreground.withAlphaComponent(0.7) : TokyoNight.muted
        }
    }

    func roundedBackgroundRect() -> NSRect {
        let visibleWidth = enclosingScrollView?.contentView.bounds.width ?? bounds.width
        let width = min(bounds.width, visibleWidth)
        let leadingInset = Self.horizontalInset + contentIndent + (isBranch ? 0 : 14)
        return NSRect(
            x: leadingInset,
            y: 2,
            width: max(0, width - Self.horizontalInset - leadingInset),
            height: max(0, bounds.height - 4)
        )
    }
}
