@preconcurrency import AppKit

final class TokyoNightOutlineRowView: NSTableRowView {
    private static let horizontalInset: CGFloat = 10
    var contentIndent: CGFloat = 0
    var isBranch = false
    var hierarchyLevel = 0
    var levelIndent: CGFloat = 14
    weak var outlineItem: PDFOutlineItem?
    var keyboardFocused = false {
        didSet { updateTextAppearance(); needsDisplay = true }
    }
    var isReadingSection = false {
        didSet { updateTextAppearance(); needsDisplay = true }
    }
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
        NSGraphicsContext.saveGraphicsState()
        if isSelected && keyboardFocused {
            let clip = NSBezierPath(rect: bounds)
            clip.append(NSBezierPath(roundedRect: roundedBackgroundRect(), xRadius: 5, yRadius: 5))
            clip.windingRule = .evenOdd
            clip.addClip()
        }
        let guides = NSBezierPath()
        for segment in hierarchyGuideSegments() {
            guides.move(to: segment.start)
            guides.line(to: segment.end)
        }
        guides.lineWidth = 1
        TokyoNight.border.withAlphaComponent(0.65).setStroke()
        guides.stroke()
        NSGraphicsContext.restoreGraphicsState()
        if isReadingSection && !(isSelected && keyboardFocused) {
            let rect = roundedBackgroundRect()
            TokyoNight.blue.withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            TokyoNight.blue.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX + 4, y: rect.midY - 3,
                                           width: 2, height: 6), xRadius: 1, yRadius: 1).fill()
        }
        if mouseInside && !isSelected {
            let hoverRect = roundedBackgroundRect()
            let path = NSBezierPath(roundedRect: hoverRect, xRadius: 5, yRadius: 5)
            TokyoNight.panelElevated.withAlphaComponent(0.35).setFill()
            path.fill()
        }
    }

    func hierarchyGuideSegments() -> [(start: NSPoint, end: NSPoint)] {
        guard let item = outlineItem,
              let outline = enclosingScrollView?.documentView as? NSOutlineView else { return [] }
        let rowIndex = outline.row(forItem: item)
        guard rowIndex >= 0 else { return [] }
        let top = isFlipped ? bounds.minY : bounds.maxY
        let bottom = isFlipped ? bounds.maxY : bounds.minY
        var segments: [(start: NSPoint, end: NSPoint)] = []
        var child = item
        while let parent = child.parent {
            let isDirectParent = child === item
            let hasNextSibling = parent.children.last !== child
            if isDirectParent || hasNextSibling {
                let parentRow = outline.row(forItem: parent)
                let x = outline.frameOfOutlineCell(atRow: parentRow).midX
                let endY = isDirectParent && !hasNextSibling ? bounds.midY : bottom
                segments.append((NSPoint(x: x, y: top), NSPoint(x: x, y: endY)))
                if isDirectParent {
                    let endX = isBranch ? outline.frameOfOutlineCell(atRow: rowIndex).minX - 3
                        : outline.frameOfCell(atColumn: 0, row: rowIndex).minX - 11
                    segments.append((NSPoint(x: x, y: bounds.midY), NSPoint(x: endX, y: bounds.midY)))
                }
            }
            child = parent
        }
        if isBranch && outline.isItemExpanded(item) {
            let disclosure = convert(outline.frameOfOutlineCell(atRow: rowIndex), from: outline)
            segments.append((NSPoint(x: disclosure.midX, y: isFlipped ? disclosure.maxY : disclosure.minY),
                             NSPoint(x: disclosure.midX, y: bottom)))
        }
        return segments
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected && keyboardFocused else { return }

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
            let isKeyboardSelection = isSelected && keyboardFocused
            cell.textField?.font = .systemFont(ofSize: isRoot ? 13 : 12.5,
                                              weight: isKeyboardSelection || isReadingSection || isRoot || isBranch ? .medium : .regular)
            cell.textField?.textColor = isKeyboardSelection ? TokyoNight.foreground : isReadingSection
                ? TokyoNight.foreground.withAlphaComponent(0.95) : isRoot
                ? TokyoNight.foreground.withAlphaComponent(0.9) : isBranch
                ? TokyoNight.foreground.withAlphaComponent(0.8) : TokyoNight.muted
            (cell as? PDFOutlineCellView)?.titleView.isSelected = isKeyboardSelection
            (cell as? PDFOutlineCellView)?.pageNumberField.textColor = isKeyboardSelection
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
