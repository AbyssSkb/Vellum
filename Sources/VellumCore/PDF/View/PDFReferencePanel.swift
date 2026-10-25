@preconcurrency import AppKit
@preconcurrency import PDFKit

@MainActor
final class PDFReferencePanel: NSView {
    let contentInset: CGFloat = 4
    let content: PDFReferenceContent
    let pdfView = ReferencePDFView()
    private var zoomMultiplier: CGFloat = 1
    private var positioned = false

    init(content: PDFReferenceContent) {
        self.content = content
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = VellumColors.background.cgColor
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.displayBox = .cropBox
        pdfView.displaysPageBreaks = false
        pdfView.backgroundColor = VellumColors.panel
        pdfView.wantsLayer = true
        pdfView.layer?.cornerRadius = 6
        pdfView.layer?.masksToBounds = true
        pdfView.autoScales = false
        pdfView.document = content.displayDocument
        addSubview(pdfView)
        updateAppearance()
    }

    required init?(coder: NSCoder) { nil }

    private func updateAppearance() {
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = VellumColors.border.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 12
        layer?.shadowOffset = NSSize(width: 0, height: -4)
        setAccessibilityElement(false)
        let language = AppUILanguage.saved()
        let title = content.title ?? .linkPreview
        setAccessibilityLabel(language.text(title) + " · " + language.text(.referencePage(content.pageNumber)))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let frame = NSRect(x: contentInset, y: contentInset,
                           width: max(1, bounds.width - contentInset * 2),
                           height: max(1, bounds.height - contentInset * 2))
        guard frame != pdfView.frame else { return }
        let crop = content.displayPage.bounds(for: .cropBox)
        let initialAnchor = content.fitsEntireCrop ? NSPoint(x: crop.midX, y: crop.midY) : content.destination.point
        let anchor = positioned ? pdfView.convert(NSPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: content.displayPage) : initialAnchor
        pdfView.frame = frame
        pdfView.layoutSubtreeIfNeeded()
        let viewport = scrollView?.contentView.frame.size ?? frame.size
        let geometry = PDFPageDisplayGeometry(page: content.displayPage, box: .cropBox)
        let widthFit = viewport.width / max(1, geometry.bounds.width)
        let fitScale = max(0.05, content.fitsEntireCrop
            ? min(widthFit, viewport.height / max(1, geometry.bounds.height)) : widthFit)
        pdfView.scaleFactor = fitScale * zoomMultiplier
        pdfView.layoutDocumentView()
        position(anchor)
        positioned = true
    }

    private func position(_ anchor: NSPoint) {
        guard let scroll = scrollView, let documentView = scroll.documentView else { return }
        let point = pdfView.convert(pdfView.convert(anchor, from: content.displayPage), to: documentView)
        let clip = scroll.contentView
        let origin = NSPoint(x: point.x - clip.bounds.width / 2, y: point.y - clip.bounds.height / 2)
        self.scroll(to: origin, in: scroll)
    }

    func zoom(by factor: CGFloat) {
        let anchor = pdfView.convert(NSPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: content.displayPage)
        let next = min(max(zoomMultiplier * factor, 1), max(16, zoomMultiplier))
        guard next != zoomMultiplier else { return }
        pdfView.scaleFactor *= next / zoomMultiplier
        zoomMultiplier = next
        pdfView.layoutDocumentView()
        position(anchor)
    }

    func scroll(by amount: CGFloat, horizontal: CGFloat = 0) {
        guard let scroll = scrollView, let documentView = scroll.documentView else { return }
        let clip = scroll.contentView
        let origin = NSPoint(x: clip.bounds.origin.x + horizontal, y: clip.bounds.origin.y + (documentView.isFlipped ? amount : -amount))
        self.scroll(to: origin, in: scroll)
    }

    private func scroll(to origin: NSPoint, in scroll: NSScrollView) {
        guard let documentView = scroll.documentView else { return }
        let clip = scroll.contentView
        let paper = pdfView.convert(pdfView.convert(content.displayPage.bounds(for: .cropBox), from: content.displayPage), to: documentView)
        let tolerance = 0.5 / pdfView.scaleFactor
        func bounded(_ value: CGFloat, _ minimum: CGFloat, _ maximum: CGFloat, _ length: CGFloat) -> CGFloat {
            if maximum - minimum <= length + tolerance { return (minimum + maximum - length) / 2 }
            return min(max(value, minimum), maximum - length)
        }
        clip.scroll(to: NSPoint(x: bounded(origin.x, paper.minX, paper.maxX, clip.bounds.width),
                               y: bounded(origin.y, paper.minY, paper.maxY, clip.bounds.height)))
        scroll.reflectScrolledClipView(clip)
    }

    var scrollView: NSScrollView? {
        func find(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { find(in: $0) }.first
        }
        return find(in: pdfView)
    }
}

@MainActor
final class ReferencePDFView: PDFView {
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        switch NSApp?.currentEvent?.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: return self
        default: return hit
        }
    }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func menu(for event: NSEvent) -> NSMenu? { nil }
}
