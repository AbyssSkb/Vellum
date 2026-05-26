@preconcurrency import AppKit

final class TokyoNightOutlineRowView: NSTableRowView {
    private static let horizontalInset: CGFloat = 10
    private var mouseInside = false {
        didSet { needsDisplay = true }
    }
    private var hoverTrackingArea: NSTrackingArea?

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
            let path = NSBezierPath(roundedRect: hoverRect, xRadius: 7, yRadius: 7)
            TokyoNight.panel.withAlphaComponent(0.38).setFill()
            path.fill()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }

        let selectionRect = roundedBackgroundRect()
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: 7, yRadius: 7)
        TokyoNight.panelElevated.withAlphaComponent(0.82).setFill()
        path.fill()

        TokyoNight.blue.withAlphaComponent(0.18).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func roundedBackgroundRect() -> NSRect {
        let visibleWidth = enclosingScrollView?.contentView.bounds.width ?? bounds.width
        let width = min(bounds.width, visibleWidth)
        return NSRect(
            x: Self.horizontalInset,
            y: 2,
            width: max(0, width - Self.horizontalInset * 2),
            height: max(0, bounds.height - 4)
        )
    }
}
