@preconcurrency import AppKit
@preconcurrency import PDFKit

extension VellumPDFView {
    var isWordJumpActive: Bool { wordJumpController?.isActive == true }

    var wordJumpViewport: NSRect {
        let viewport = bounds.intersection(visibleRect)
        guard let clipView = pdfScrollView?.contentView else { return viewport }
        return convert(clipView.bounds, from: clipView).intersection(viewport)
    }

    func beginWordJumpCommand() {
        if wordJumpController == nil { wordJumpController = PDFWordJumpController(pdfView: self) }
        wordJumpController?.begin()
        updateSelectionEndpointOverlay()
    }

    func beginLinkJumpCommand() {
        if wordJumpController == nil { wordJumpController = PDFWordJumpController(pdfView: self) }
        wordJumpController?.begin(mode: .followLinks)
        updateSelectionEndpointOverlay()
    }

    func handleWordJumpKey(_ event: NSEvent) -> Bool {
        defer { updateSelectionEndpointOverlay() }
        return wordJumpController?.handleKey(event) ?? false
    }

    func cancelWordJump() {
        wordJumpController?.cancel()
        updateSelectionEndpointOverlay()
    }
}

struct PDFWordJumpTarget {
    let selection: PDFSelection?
    let word: String
    let rects: [NSRect]
    let link: PDFAnnotation?

    var rotation: Int { selection?.pages.first?.rotation ?? link?.page?.rotation ?? 0 }
}

enum WordJumpLabelGeometry {
    static func fontSize(for word: NSRect, rotation: Int = 0) -> CGFloat {
        let height = rotation % 180 == 0 ? word.height : word.width
        return min(20, max(12, height * 0.8))
    }

    static func frame(for word: NSRect, labelSize: NSSize, in viewport: NSRect, avoiding occupied: [NSRect]) -> NSRect {
        let bounds = viewport.insetBy(dx: 2, dy: 2)
        let size = NSSize(width: min(labelSize.width, bounds.width), height: min(labelSize.height, bounds.height))
        let gap: CGFloat = 2
        let right = NSPoint(x: word.maxX + gap, y: word.midY - size.height / 2)
        let left = NSPoint(x: word.minX - size.width - gap, y: right.y)
        let obstacles = occupied + [word]
        var best = NSRect.zero
        var leastOverlap = CGFloat.greatestFiniteMagnitude

        func place(_ origin: NSPoint) -> NSRect? {
            let frame = NSRect(x: min(max(origin.x, bounds.minX), bounds.maxX - size.width),
                               y: min(max(origin.y, bounds.minY), bounds.maxY - size.height),
                               width: size.width, height: size.height)
            let overlap = obstacles.reduce(CGFloat.zero) { area, obstacle in
                let padded = obstacle.insetBy(dx: -1, dy: -1)
                guard frame.intersects(padded) else { return area }
                let intersection = frame.intersection(padded)
                return area + intersection.width * intersection.height
            }
            if overlap < leastOverlap {
                best = frame
                leastOverlap = overlap
            }
            return overlap == 0 ? frame : nil
        }

        for origin in [right, left,
                       NSPoint(x: word.minX, y: word.maxY + gap),
                       NSPoint(x: word.minX, y: word.minY - size.height - gap)] {
            if let frame = place(origin) { return frame }
        }
        for step in 1...max(1, Int(ceil(bounds.height / (size.height + gap)))) {
            let offset = CGFloat(step) * (size.height + gap)
            for origin in [NSPoint(x: right.x, y: right.y + offset),
                           NSPoint(x: right.x, y: right.y - offset),
                           NSPoint(x: left.x, y: left.y + offset),
                           NSPoint(x: left.x, y: left.y - offset)] {
                if let frame = place(origin) { return frame }
            }
        }
        // shortcut: Filled nearby columns use the least overlap; widen placement if dense prefixes need it.
        return best
    }
}

@MainActor
final class PDFWordJumpController {
    private weak var pdfView: VellumPDFView?
    private weak var document: PDFDocument?
    private var overlay: WordJumpOverlayView?
    private var viewport = NSRect.zero
    private var scale: CGFloat = 1
    private var mode = Mode.words
    private(set) var targets: [PDFWordJumpTarget] = []
    private(set) var session = WordJumpSession(words: [])

    var isActive: Bool { overlay != nil }

    init(pdfView: VellumPDFView) { self.pdfView = pdfView }

    enum Mode {
        case words, lookupWord, followLinks, previewLinks

        var selectsWords: Bool { self == .words || self == .lookupWord }
    }

    func begin(mode: Mode = .words) {
        cancel()
        guard let pdfView, let document = pdfView.document else { return }
        pdfView.cancelLinkPreview()
        pdfView.completePendingRestoreBeforeUserInteraction()
        pdfView.cancelPendingRestore()
        pdfView.stopScrollAnimation()
        pdfView.stopZoomState()
        pdfView.hideAIExplanationPopover()
        _ = pdfView.searchController?.handleEscape()
        pdfView.focus()
        self.document = document
        self.mode = mode
        viewport = pdfView.wordJumpViewport
        scale = pdfView.scaleFactor
        targets = mode.selectsWords ? visibleWords(in: pdfView, document: document) : visibleLinks(in: pdfView, document: document)
        guard !targets.isEmpty else {
            cancel()
            let reason: AppText = mode.selectsWords ? .wordJumpNoText : (mode == .previewLinks ? .linkPreviewNoLinks : .linkJumpNoLinks)
            pdfView.showNotification(AppUILanguage.saved().text(reason))
            return
        }
        session = WordJumpSession(words: targets.map(\.word), labelsOnly: !mode.selectsWords)
        let overlay = WordJumpOverlayView(frame: pdfView.bounds)
        overlay.autoresizingMask = [.width, .height]
        pdfView.addSubview(overlay)
        self.overlay = overlay
        refreshOverlay()
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard isActive else { return false }
        cancelIfViewportChanged()
        guard isActive else { return true }
        guard event.type == .keyDown else { return true }
        guard !event.isARepeat, let key = event.charactersIgnoringModifiers else { return true }
        switch session.input(key) {
        case .updated:
            refreshOverlay()
        case .cancelled:
            cancel()
        case .selected(let index):
            let target = targets[index]
            let selectedMode = mode
            cancel()
            if let link = target.link, selectedMode == .previewLinks {
                pdfView?.showLinkPreview(for: link)
            } else if let link = target.link, let action = PDFLinkNavigation.action(for: link) {
                pdfView?.clearTextSelectionForVimNavigation()
                pdfView?.vimPerformPDFAction(action)
            } else if let selection = target.selection {
                selection.color = nil
                pdfView?.textSelectionNavigationState = nil
                pdfView?.setCurrentSelection(selection, animate: false)
            }
            pdfView?.focus()
            if selectedMode == .lookupWord, target.selection != nil {
                pdfView?.vimLookupDictionary()
            }
        }
        return true
    }

    func cancel() {
        overlay?.removeFromSuperview()
        overlay = nil
        targets = []
        session = WordJumpSession(words: [])
        mode = .words
        document = nil
    }

    func cancelIfViewportChanged() {
        guard isActive, let pdfView else { return }
        if pdfView.document !== document || pdfView.wordJumpViewport != viewport || pdfView.scaleFactor != scale {
            cancel()
        }
    }

    private func visibleWords(in pdfView: VellumPDFView, document: PDFDocument) -> [PDFWordJumpTarget] {
        var targets: [PDFWordJumpTarget] = []
        for page in pdfView.visiblePages.sorted(by: { document.index(for: $0) < document.index(for: $1) }) {
            guard let text = pdfView.textSelectionCache.text(on: page, in: document) else { continue }
            var index = 0
            var ranges: Set<NSRange> = []
            while index < text.length {
                guard TextWordNavigator.characterClass(at: index, in: text) == .word else {
                    index += 1
                    continue
                }
                let end = TextWordNavigator.wordEndOffset(from: index, in: text)
                let range = VellumPDFView.hyphenatedWordRange(in: text, selectedRange: NSRange(location: index, length: end - index))
                index = end
                guard ranges.insert(range).inserted else { continue }
                guard let selection = page.selection(for: range) else { continue }
                let rects = selection.selectionsByLine().compactMap { line in
                    pdfView.viewRect(for: line.bounds(for: page), on: page)
                }.filter { !$0.isEmpty && $0.intersects(viewport) }
                guard !rects.isEmpty else { continue }
                let word = text.substring(with: range).filter { $0.isLetter || $0.isNumber || $0 == "_" }
                targets.append(PDFWordJumpTarget(selection: selection, word: word, rects: rects, link: nil))
            }
        }
        return targets
    }

    private func visibleLinks(in pdfView: VellumPDFView, document: PDFDocument) -> [PDFWordJumpTarget] {
        pdfView.visiblePages.sorted(by: { document.index(for: $0) < document.index(for: $1) }).flatMap { page in
            page.annotations.compactMap { annotation in
                guard annotation.type == "Link", annotation.shouldDisplay,
                      PDFLinkNavigation.action(for: annotation) != nil else { return nil }
                if mode == .previewLinks,
                   PDFLinkNavigation.previewDestination(for: annotation, in: document) == nil { return nil }
                let bounds = annotation.bounds.intersection(page.bounds(for: pdfView.displayBox))
                guard !bounds.isEmpty, let rect = pdfView.viewRect(for: bounds, on: page),
                      rect.intersects(viewport) else { return nil }
                let text = page.selection(for: bounds)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = text.flatMap { $0.isEmpty ? nil : $0 }
                    ?? annotation.url?.absoluteString ?? AppUILanguage.saved().text(.linkJump)
                return PDFWordJumpTarget(selection: nil, word: title,
                                         rects: [rect.intersection(viewport)], link: annotation)
            }
        }
    }

    private func refreshOverlay() {
        guard let overlay else { return }
        overlay.targets = targets
        overlay.session = session
        overlay.isLinkPreview = mode == .previewLinks
        overlay.setAccessibilityLabel(AppUILanguage.saved().text(mode.selectsWords ? .wordJump : (mode == .previewLinks ? .linkPreview : .linkJump)))
        overlay.needsDisplay = true
        overlay.setAccessibilityValue(overlay.statusText + ". " + session.displayedMatches.map {
            "\($0.label): \(targets[$0.wordIndex].word)"
        }.joined(separator: ", "))
    }
}

@MainActor
private final class WordJumpOverlayView: NSView {
    var targets: [PDFWordJumpTarget] = []
    var session = WordJumpSession(words: [])
    var isLinkPreview = false
    private var labelFrames: [Int: NSRect] = [:]

    var statusText: String {
        statusText(labelPrefix: session.labelPrefix, count: session.displayedMatches.count)
    }

    private func statusText(labelPrefix: String, count: Int) -> String {
        let language = AppUILanguage.saved()
        if session.labelsOnly {
            let detail = language.text(.linkJumpTypeHint) + (labelPrefix.isEmpty ? "" : "  →  " + labelPrefix)
                + "  ·  " + String(count)
            return "\(language.text(isLinkPreview ? .linkPreview : .linkJump))   \(detail)"
        }
        let detail = session.query.isEmpty ? language.text(.wordJumpTypeHint)
            : session.query + (labelPrefix.isEmpty ? "" : "  →  " + labelPrefix)
                + "  ·  " + (session.matches.isEmpty ? language.text(.searchNoMatch) : String(count))
        return "\(language.text(.wordJump))   \(detail)"
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(AppUILanguage.saved().text(.wordJump))
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var viewport: NSRect {
        guard let pdfView = superview as? VellumPDFView else { return bounds.intersection(visibleRect) }
        return convert(pdfView.wordJumpViewport, from: pdfView)
    }

    private var statusFrame: NSRect {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]
        // Reserve complete label entry so the HUD does not displace nearby labels while typing.
        let textWidth = session.matches.reduce((statusText as NSString).size(withAttributes: attributes).width) { width, match in
            let text = statusText(labelPrefix: match.label, count: session.matches.count) as NSString
            return max(width, text.size(withAttributes: attributes).width)
        }
        let width = min(viewport.width - 32, textWidth + 28)
        return NSRect(x: viewport.midX - width / 2, y: viewport.minY + 18, width: width, height: 30)
    }

    private func updateLabelFrames() {
        let candidates = session.matches.compactMap { match -> (index: Int, word: NSRect, size: NSSize)? in
            guard !match.label.isEmpty, let rect = targets[match.wordIndex].rects.first else { return nil }
            let word = convert(rect, from: superview)
            let rotation = targets[match.wordIndex].rotation
            let font = NSFont.monospacedSystemFont(ofSize: WordJumpLabelGeometry.fontSize(for: word, rotation: rotation), weight: .bold)
            let textSize = (match.label as NSString).size(withAttributes: [.font: font])
            return (match.wordIndex, word,
                    NSSize(width: textSize.width + font.pointSize * 2 / 3, height: textSize.height + font.pointSize / 4))
        }
        let previous = labelFrames
        labelFrames = [:]
        var occupied = [statusFrame]
        for candidate in candidates {
            if let frame = previous[candidate.index], frame.size == candidate.size,
               viewport.insetBy(dx: 2, dy: 2).contains(frame),
               !occupied.contains(where: { frame.intersects($0.insetBy(dx: -1, dy: -1)) }) {
                labelFrames[candidate.index] = frame
                occupied.append(frame)
            }
        }
        for candidate in candidates where labelFrames[candidate.index] == nil {
            let frame = WordJumpLabelGeometry.frame(for: candidate.word, labelSize: candidate.size,
                                                   in: viewport, avoiding: occupied)
            labelFrames[candidate.index] = frame
            occupied.append(frame)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        updateLabelFrames()
        for match in session.displayedMatches {
            let rects = targets[match.wordIndex].rects.map { convert($0, from: superview) }
            VellumColors.cyan.withAlphaComponent(0.3).setFill()
            for rect in rects {
                NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: 2, yRadius: 2).fill()
            }
        }
        for match in session.displayedMatches {
            guard let frame = labelFrames[match.wordIndex],
                  let word = targets[match.wordIndex].rects.first else { continue }
            let rect = convert(word, from: superview)
            let label = String(match.label.dropFirst(session.labelPrefix.count)) as NSString
            let rotation = targets[match.wordIndex].rotation
            let fontSize = WordJumpLabelGeometry.fontSize(for: rect, rotation: rotation)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: VellumColors.backgroundDeep
            ]
            let size = label.size(withAttributes: attributes)
            let end = NSPoint(x: min(max(rect.midX, frame.minX), frame.maxX),
                              y: min(max(rect.midY, frame.minY), frame.maxY))
            let start = NSPoint(x: min(max(end.x, rect.minX), rect.maxX),
                                y: min(max(end.y, rect.minY), rect.maxY))
            if hypot(end.x - start.x, end.y - start.y) > 6 {
                VellumColors.cyan.withAlphaComponent(0.65).setStroke()
                let connection = NSBezierPath()
                connection.move(to: start)
                connection.line(to: end)
                connection.lineWidth = 1
                connection.stroke()
            }
            VellumColors.cyan.setFill()
            NSBezierPath(roundedRect: frame, xRadius: fontSize / 4, yRadius: fontSize / 4).fill()
            label.draw(at: NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2),
                       withAttributes: attributes)
        }

        let text = statusText as NSString
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: VellumColors.foreground,
            .paragraphStyle: paragraph
        ]
        let size = text.size(withAttributes: attributes)
        let frame = statusFrame
        VellumColors.backgroundDeep.setFill()
        let path = NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
        path.fill()
        VellumColors.border.setStroke()
        path.lineWidth = 1
        path.stroke()
        text.draw(in: NSRect(x: frame.minX + 14, y: frame.midY - size.height / 2,
                            width: frame.width - 28, height: size.height), withAttributes: attributes)
    }
}
