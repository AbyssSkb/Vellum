@preconcurrency import AppKit
@preconcurrency import PDFKit

extension VellumPDFView {
    func beginLinkPreviewCommand() {
        if wordJumpController == nil { wordJumpController = PDFWordJumpController(pdfView: self) }
        wordJumpController?.begin(mode: .previewLinks)
        updateSelectionEndpointOverlay()
    }

    func showLinkPreview(for annotation: PDFAnnotation) {
        guard let document,
              let destination = PDFLinkNavigation.previewDestination(for: annotation, in: document) else {
            showNotification(AppUILanguage.saved().text(.referenceUnavailable))
            return
        }
        let crop: NSRect?
        let fitsEntireCrop: Bool
        let title: AppText?
        let resolvedDestination: PDFDestination
        let continuation: (page: PDFPage, bounds: CGRect)?
        let additionalFragments: [(page: PDFPage, bounds: CGRect)]
        switch PDFReferencePreview.resolve(for: annotation, destination: destination) {
        case .region(let region):
            crop = region.bounds
            fitsEntireCrop = true
            title = region.title
            resolvedDestination = region.destination ?? destination
            continuation = region.continuation
            additionalFragments = region.additionalFragments
        case .pageContext:
            crop = nil
            fitsEntireCrop = false
            title = nil
            resolvedDestination = destination
            continuation = nil
            additionalFragments = []
        }
        guard let content = PDFReferenceContent(document: document, destination: resolvedDestination, crop: crop,
                                                fitsEntireCrop: fitsEntireCrop, title: title,
                                                continuation: continuation, additionalFragments: additionalFragments) else {
            showNotification(AppUILanguage.saved().text(.referenceUnavailable))
            return
        }
        if referenceController == nil { referenceController = PDFReferenceController(reader: self) }
        referenceController?.show(content, sourceRect: annotation.page.flatMap { viewRect(for: annotation.bounds, on: $0) })
    }

    func handleReferencePreviewKey(_ event: NSEvent) -> Bool {
        referenceController?.handleKey(event) ?? false
    }

    func cancelLinkPreview() {
        referenceController?.closePreview()
    }

    func clearPDFReferences() {
        referenceController?.clear()
        referenceController = nil
    }
}

@MainActor
final class PDFReferenceContent {
    weak var sourceDocument: PDFDocument?
    let sourcePage: PDFPage
    let pageNumber: Int
    let destination: PDFDestination
    let displayDocument: PDFDocument
    let displayPage: PDFPage
    let fitsEntireCrop: Bool
    let title: AppText?
    private let continuationPages: [PDFPage]

    init?(document: PDFDocument, destination: PDFDestination, crop: NSRect? = nil,
          fitsEntireCrop: Bool = false, title: AppText? = nil,
          continuation: (page: PDFPage, bounds: CGRect)? = nil,
          additionalFragments: [(page: PDFPage, bounds: CGRect)] = []) {
        guard let page = destination.page, page.document === document,
              document.index(for: page) != NSNotFound else { return nil }
        let previewDocument: PDFDocument
        let continuations = continuation.map { [$0] } ?? []
        let fragments = continuations + additionalFragments
        if !fragments.isEmpty {
            let alignsFragments: Bool
            switch title {
            case .some(.sectionPreview), .some(.tablePreview): alignsFragments = true
            default: alignsFragments = false
            }
            guard let crop, fragments.allSatisfy({ $0.page.document === document && document.index(for: $0.page) != NSNotFound }),
                  let combined = Self.combinedDocument(fragments: [(page, crop)] + fragments, alignsFragments: alignsFragments) else { return nil }
            previewDocument = combined
        } else {
            guard let data = page.dataRepresentation,
                  let independent = PDFDocument(data: data),
                  let copy = independent.page(at: 0) else { return nil }
            let bounds = page.bounds(for: .cropBox)
            guard !bounds.isEmpty else { return nil }
            if let crop {
                let visible = crop.intersection(bounds)
                guard !visible.isEmpty else { return nil }
                // PDFPage.copy() shares its CGPDFPage; cropping requires an independent document.
                copy.setBounds(visible, for: .cropBox)
            }
            previewDocument = independent
        }
        guard let copy = previewDocument.page(at: 0) else { return nil }
        sourceDocument = document
        sourcePage = page
        continuationPages = fragments.map(\.page)
        self.fitsEntireCrop = fitsEntireCrop
        self.title = title
        pageNumber = document.index(for: page) + 1
        self.destination = PDFDestination(page: page, at: Self.normalizedPoint(destination.point, on: page))
        displayPage = copy
        displayDocument = previewDocument
    }

    private static func combinedDocument(fragments: [(page: PDFPage, bounds: CGRect)], alignsFragments: Bool) -> PDFDocument? {
        var drawing: [(page: CGPDFPage, source: PDFPage, transform: CGAffineTransform, bounds: CGRect)] = []
        for fragment in fragments {
            let bounds = fragment.bounds
            guard [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite),
                  bounds.width > 0, bounds.height > 0, let page = fragment.page.pageRef else { return nil }
            let visible = bounds.intersection(fragment.page.bounds(for: .cropBox))
            guard !visible.isEmpty else { return nil }
            let geometry = PDFPageDisplayGeometry(page: fragment.page, box: .cropBox)
            let transform = page.getDrawingTransform(.cropBox, rect: geometry.bounds,
                rotate: Int32(fragment.page.rotation - Int(page.rotationAngle)), preserveAspectRatio: true)
            drawing.append((page, fragment.page, transform, geometry.rect(forPageRect: visible)))
        }
        let gap: CGFloat = 4
        let left = drawing.map(\.bounds.minX).min() ?? 0
        let right = drawing.map(\.bounds.maxX).max() ?? 0
        var media = CGRect(x: 0, y: 0, width: alignsFragments ? drawing.map(\.bounds.width).max() ?? 0 : right - left,
                           height: drawing.reduce(0) { $0 + $1.bounds.height } + gap * CGFloat(max(0, drawing.count - 1)))
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { return nil }
        context.beginPDFPage(nil)
        var top = media.maxY
        for fragment in drawing {
            let output = CGRect(x: alignsFragments ? 0 : fragment.bounds.minX - left, y: top - fragment.bounds.height, width: fragment.bounds.width,
                                height: fragment.bounds.height)
            context.saveGState()
            context.clip(to: output)
            context.translateBy(x: output.minX - fragment.bounds.minX, y: output.minY - fragment.bounds.minY)
            context.saveGState()
            context.concatenate(fragment.transform)
            context.drawPDFPage(fragment.page)
            context.restoreGState()
            // PDFKit draws annotations in displayed crop coordinates, including rotation.
            for annotation in fragment.source.annotations where annotation.shouldDisplay {
                annotation.draw(with: .cropBox, in: context)
            }
            context.restoreGState()
            top = output.minY - gap
        }
        context.endPDFPage()
        context.closePDF()
        return PDFDocument(data: data as Data)
    }

    func isValid(in document: PDFDocument?) -> Bool {
        guard let document else { return false }
        guard continuationPages.allSatisfy({ $0.document === document && document.index(for: $0) != NSNotFound }) else { return false }
        return sourceDocument === document && sourcePage.document === document
            && document.index(for: sourcePage) != NSNotFound
    }

    static func normalizedPoint(_ point: NSPoint, on page: PDFPage) -> NSPoint {
        let geometry = PDFPageDisplayGeometry(page: page, box: .cropBox)
        // FitH/FitV may omit only one axis; retain the supplied coordinate.
        let fallback = geometry.pagePoint(forDisplayPoint: NSPoint(x: geometry.bounds.midX, y: geometry.bounds.maxY))
        let supplied = NSPoint(x: point.x.isFinite && abs(point.x) < 1e10 ? point.x : fallback.x,
                               y: point.y.isFinite && abs(point.y) < 1e10 ? point.y : fallback.y)
        let displayed = geometry.point(forPagePoint: supplied)
        return geometry.pagePoint(forDisplayPoint: NSPoint(
            x: min(max(displayed.x, geometry.bounds.minX), geometry.bounds.maxX),
            y: min(max(displayed.y, geometry.bounds.minY), geometry.bounds.maxY)
        ))
    }
}

@MainActor
final class PDFReferenceController {
    private weak var reader: VellumPDFView?
    private(set) var preview: PDFReferencePanel?
    private var sourceRect: NSRect?
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    init(reader: VellumPDFView) { self.reader = reader }

    var isPreviewActive: Bool { preview != nil }

    func show(_ content: PDFReferenceContent, sourceRect: NSRect?) {
        closePreview()
        guard let reader else { return }
        self.sourceRect = sourceRect
        let panel = PDFReferencePanel(content: content)
        preview = panel
        reader.addSubview(panel)
        layoutPreview()
        reader.focus()
        reader.updateSelectionEndpointOverlay()
        monitorDismissal()
    }

    func layoutPreview() {
        guard let reader, let preview else { return }
        guard preview.content.isValid(in: reader.document) else { closePreview(); return }
        let viewport = reader.wordJumpViewport.insetBy(dx: 12, dy: 12)
        guard viewport.width > 0, viewport.height > 0 else { closePreview(); return }
        var width = viewport.width * 0.6
        var height = viewport.height * 0.6
        if preview.content.fitsEntireCrop {
            let page = PDFPageDisplayGeometry(page: preview.content.displayPage, box: .cropBox).bounds
            let inset = preview.contentInset * 2
            let scale = min(max(1, width - inset) / page.width, max(1, height - inset) / page.height)
            width = min(width, page.width * scale + inset)
            height = min(height, page.height * scale + inset)
        }
        let anchor = sourceRect ?? NSRect(x: viewport.midX, y: viewport.midY, width: 0, height: 0)
        let below = reader.isFlipped ? anchor.maxY + 10 : anchor.minY - height - 10
        let above = reader.isFlipped ? anchor.minY - height - 10 : anchor.maxY + 10
        let preferredY = below >= viewport.minY && below + height <= viewport.maxY ? below : above
        preview.frame = NSRect(
            x: min(max(anchor.midX - width / 2, viewport.minX), viewport.maxX - width),
            y: min(max(preferredY, viewport.minY), viewport.maxY - height),
            width: width, height: height
        )
        preview.layoutSubtreeIfNeeded()
    }

    func closePreview() {
        preview?.removeFromSuperview()
        preview = nil
        sourceRect = nil
        stopMonitoring()
        reader?.updateSelectionEndpointOverlay()
    }

    func clear() {
        closePreview()
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard let reader else { return false }
        let key = event.charactersIgnoringModifiers ?? ""
        if Self.focusDirection(for: event) != nil { return preview != nil }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            closePreview()
            return false
        }
        guard let panel = preview else { return false }
        guard panel.content.isValid(in: reader.document) else {
            closePreview()
            reader.showNotification(AppUILanguage.saved().text(.referenceUnavailable))
            return true
        }
        guard event.type == .keyDown else { return true }
        switch key {
        case "\u{1b}":
            if !event.isARepeat { closePreview() }
        case "x":
            if !event.isARepeat {
                closePreview()
                reader.focus()
            }
        case "p", "\r", "\n":
            if !event.isARepeat { follow(panel.content) }
        case "j", "k":
            panel.scroll(by: key == "j" ? 36 : -36)
        case "h", "l":
            panel.scroll(by: 0, horizontal: key == "l" ? 36 : -36)
        case "d", "u":
            panel.scroll(by: panel.pdfView.bounds.height * (key == "d" ? 0.5 : -0.5))
        case "f", "b", " ":
            panel.scroll(by: panel.pdfView.bounds.height * (key == "b" ? -0.85 : 0.85))
        case "=", "+", "-":
            panel.zoom(by: key == "-" ? 1 / 1.2 : 1.2)
        default:
            break
        }
        return true
    }

    private func follow(_ content: PDFReferenceContent) {
        guard let reader else { return }
        closePreview()
        guard content.isValid(in: reader.document) else {
            reader.showNotification(AppUILanguage.saved().text(.referenceUnavailable))
            return
        }
        reader.clearTextSelectionForVimNavigation()
        reader.vimGoToDestination(content.destination)
        reader.focus()
    }

    enum FocusDirection { case left, down, up, right }

    static func focusDirection(for event: NSEvent) -> FocusDirection? {
        guard event.modifierFlags.contains(.control),
              event.modifierFlags.intersection([.command, .option]).isEmpty else { return nil }
        switch event.charactersIgnoringModifiers?.lowercased() ?? "" {
        case "h", "\u{8}": return .left
        case "j", "\u{a}": return .down
        case "k", "\u{b}": return .up
        case "l", "\u{c}": return .right
        default:
            switch event.keyCode {
            case 4: return .left
            case 38: return .down
            case 40: return .up
            case 37: return .right
            default: return nil
            }
        }
    }

    private func monitorDismissal() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.reader?.window else { return }
                guard let panel = self.preview else { return }
                if !panel.bounds.contains(panel.convert(event.locationInWindow, from: nil)) { self.closePreview() }
            }
            return event
        }
        observers = [NSWindow.didResignKeyNotification, NSApplication.didResignActiveNotification].map { name in
            let object: Any? = name == NSWindow.didResignKeyNotification ? reader?.window : nil
            return NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.closePreview()
                }
            }
        }
    }

    private func stopMonitoring() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}
