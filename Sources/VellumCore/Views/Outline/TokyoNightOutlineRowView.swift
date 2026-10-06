@preconcurrency import AppKit

final class TokyoNightOutlineRowView: NSTableRowView {
    private static let horizontalInset: CGFloat = 10
    var contentIndent: CGFloat = 0
    var isBranch = false
    var hierarchyLevel = 0
    var levelIndent: CGFloat = 14
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
        TokyoNight.border.withAlphaComponent(0.65).setFill()
        for level in 0..<hierarchyLevel {
            NSRect(x: 14 + CGFloat(level) * levelIndent, y: 0, width: 0.5, height: bounds.height).fill()
        }
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
            let isRoot = hierarchyLevel == 0
            cell.textField?.font = .systemFont(ofSize: isRoot ? 13 : 12.5,
                                              weight: isSelected || isRoot || isBranch ? .medium : .regular)
            cell.textField?.textColor = isSelected ? TokyoNight.foreground : isRoot
                ? TokyoNight.foreground.withAlphaComponent(0.9) : isBranch
                ? TokyoNight.foreground.withAlphaComponent(0.8) : TokyoNight.muted
            (cell as? PDFOutlineCellView)?.titleView.isSelected = isSelected
            (cell as? PDFOutlineCellView)?.pageNumberField.textColor = isSelected
                ? TokyoNight.foreground.withAlphaComponent(0.75) : TokyoNight.muted.withAlphaComponent(0.8)
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
