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

    @MainActor
    func labelArea(characterCount: Int, in pdfView: VellumPDFView) -> (rect: NSRect, characterCount: Int)? {
        guard let selection, let document = pdfView.document, characterCount > 0 else { return nil }
        let lines = selection.selectionsByLine()
        for line in lines.isEmpty ? [selection] : lines {
            for page in line.pages {
                guard let text = pdfView.textSelectionCache.text(on: page, in: document) else { continue }
                for rangeIndex in 0..<line.numberOfTextRanges(on: page) {
                    let range = line.range(at: rangeIndex, on: page)
                    guard range.location != NSNotFound, range.location < text.length else { continue }
                    let end = min(NSMaxRange(range), text.length)
                    var index = range.location
                    var area: NSRect?
                    var count = 0
                    while index < end, count < characterCount {
                        let characterRange = text.rangeOfComposedCharacterSequence(at: index)
                        index = NSMaxRange(characterRange)
                        guard characterRange.location >= range.location, index <= end,
                              let character = text.substring(with: characterRange).first,
                              character.isLetter || character.isNumber || character == "_",
                              let characterSelection = page.selection(for: characterRange) else { continue }
                        let bounds = characterSelection.bounds(for: page).intersection(page.bounds(for: pdfView.displayBox))
                        guard !bounds.isEmpty, let rect = pdfView.viewRect(for: bounds, on: page),
                              rect.intersects(pdfView.wordJumpViewport) else { continue }
                        area = area.map { $0.union(rect) } ?? rect
                        count += 1
                    }
                    if let area { return (area, count) }
                }
            }
        }
        return nil
    }
}

enum WordJumpLabelGeometry {
    static func visibleLabel(_ label: String, typedPrefix: String, characterCount: Int) -> String {
        label.count <= characterCount ? label : String(label.dropFirst(typedPrefix.count).prefix(characterCount))
    }

    static func fontSize(for word: NSRect, rotation: Int = 0) -> CGFloat {
        let height = rotation % 180 == 0 ? word.height : word.width
        return min(14, max(11, height * 0.72))
    }

    static func frame(for word: NSRect, labelSize: NSSize, in viewport: NSRect,
                      avoiding occupied: [NSRect], rotation: Int = 0) -> NSRect {
        let bounds = viewport.insetBy(dx: 2, dy: 2)
        let size = NSSize(width: min(labelSize.width, bounds.width), height: min(labelSize.height, bounds.height))
        let rotation = (rotation % 360 + 360) % 360
        let vertical = rotation % 180 != 0
        let origin: NSPoint
        switch rotation {
        case 90: origin = NSPoint(x: word.midX - size.width / 2, y: word.maxY - size.height)
        case 180: origin = NSPoint(x: word.maxX - size.width, y: word.midY - size.height / 2)
        case 270: origin = NSPoint(x: word.midX - size.width / 2, y: word.minY)
        default: origin = NSPoint(x: word.minX, y: word.midY - size.height / 2)
        }
        let crossSize = vertical ? size.width : size.height
        let wordCrossSize = vertical ? word.width : word.height
        let offset = max(0, min(crossSize + 1, (wordCrossSize + crossSize) / 2 - 2))
        var best = NSRect.zero
        var leastOverlap = CGFloat.greatestFiniteMagnitude
        for shift in [CGFloat.zero, offset, -offset] {
            let frame = NSRect(x: min(max(origin.x + (vertical ? shift : 0), bounds.minX), bounds.maxX - size.width),
                               y: min(max(origin.y + (vertical ? 0 : shift), bounds.minY), bounds.maxY - size.height),
                               width: size.width, height: size.height)
            let overlap = occupied.reduce(CGFloat.zero) { area, obstacle in
                guard frame.intersects(obstacle) else { return area }
                let intersection = frame.intersection(obstacle)
                return area + intersection.width * intersection.height
            }
            if overlap < leastOverlap {
                best = frame
                leastOverlap = overlap
            }
            if overlap == 0 { return frame }
        }
        return best
    }
}

@MainActor
final class PDFWordJumpController {
    private weak var pdfView: VellumPDFView?
    private weak var document: PDFDocument?
    private var overlay: WordJumpOverlayView?
    private weak var entryHint: ToastView?
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
        if mode.selectsWords {
            entryHint = VellumToast.show(AppUILanguage.saved().text(.wordJumpTypeHint),
                                        in: pdfView.window, autoDismiss: false)
        }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard isActive else { return false }
        cancelIfViewportChanged()
        guard isActive else { return true }
        guard event.type == .keyDown else { return true }
        guard !event.isARepeat, let key = event.charactersIgnoringModifiers else { return true }
        switch session.input(key) {
        case .updated:
            if mode.selectsWords, !session.query.isEmpty {
                guard !session.matches.isEmpty else {
                    cancel()
                    pdfView?.showNotification(AppUILanguage.saved().text(.wordJumpNoMatch))
                    return true
                }
                entryHint?.dismiss(animated: false)
                entryHint = nil
            }
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
        entryHint?.dismiss(animated: false)
        entryHint = nil
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
    private var labelCharacterCounts: [Int: Int] = [:]

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
        let previous = labelFrames
        labelFrames = [:]
        labelCharacterCounts = [:]
        let candidates = session.matches.compactMap { match -> (index: Int, word: NSRect, size: NSSize)? in
            guard !match.label.isEmpty, let rect = targets[match.wordIndex].rects.first else { return nil }
            if !session.labelsOnly, let pdfView = superview as? VellumPDFView,
               let area = targets[match.wordIndex].labelArea(characterCount: match.label.count, in: pdfView) {
                labelFrames[match.wordIndex] = convert(area.rect, from: pdfView)
                labelCharacterCounts[match.wordIndex] = area.characterCount
                return nil
            }
            let word = convert(rect, from: superview)
            let rotation = targets[match.wordIndex].rotation
            let font = NSFont.monospacedSystemFont(ofSize: WordJumpLabelGeometry.fontSize(for: word, rotation: rotation), weight: .medium)
            let textSize = (match.label as NSString).size(withAttributes: [.font: font])
            return (match.wordIndex, word,
                    NSSize(width: textSize.width + 4, height: textSize.height))
        }
        var occupied = session.labelsOnly ? [statusFrame] : Array(labelFrames.values)
        for candidate in candidates {
            if let frame = previous[candidate.index], frame.size == candidate.size,
               viewport.insetBy(dx: 2, dy: 2).contains(frame) {
                labelFrames[candidate.index] = frame
                occupied.append(frame)
            }
        }
        for candidate in candidates where labelFrames[candidate.index] == nil {
            let frame = WordJumpLabelGeometry.frame(for: candidate.word, labelSize: candidate.size,
                                                   in: viewport, avoiding: occupied,
                                                   rotation: targets[candidate.index].rotation)
            labelFrames[candidate.index] = frame
            occupied.append(frame)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: viewport).addClip()
        defer { NSGraphicsContext.restoreGraphicsState() }
        updateLabelFrames()
        for match in session.displayedMatches where match.label.isEmpty {
            let rects = targets[match.wordIndex].rects.map { convert($0, from: superview) }
            VellumColors.blue.withAlphaComponent(0.14).setFill()
            for rect in rects {
                NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: 2, yRadius: 2).fill()
            }
        }
        for match in session.displayedMatches {
            guard let frame = labelFrames[match.wordIndex],
                  let word = targets[match.wordIndex].rects.first else { continue }
            let rect = convert(word, from: superview)
            let usesTextGeometry = labelCharacterCounts[match.wordIndex] != nil
            let characterCount = labelCharacterCounts[match.wordIndex] ?? match.label.count
            let showsRemainingLetters = characterCount < match.label.count
            let label = WordJumpLabelGeometry.visibleLabel(match.label, typedPrefix: session.labelPrefix,
                                                         characterCount: characterCount) as NSString
            let rotation = usesTextGeometry ? (targets[match.wordIndex].rotation % 360 + 360) % 360 : 0
            let textArea = rotation % 180 == 0 ? frame.size : NSSize(width: frame.height, height: frame.width)
            let fontSize = usesTextGeometry ? textArea.height * 0.8
                : WordJumpLabelGeometry.fontSize(for: rect, rotation: targets[match.wordIndex].rotation)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: VellumColors.foreground
            ]
            let size = label.size(withAttributes: attributes)
            VellumColors.panel.setFill()
            let path = usesTextGeometry ? NSBezierPath(rect: frame)
                : NSBezierPath(roundedRect: frame, xRadius: 2, yRadius: 2)
            path.fill()
            let text = NSMutableAttributedString(string: label as String, attributes: attributes)
            text.addAttribute(.foregroundColor, value: VellumColors.muted.withAlphaComponent(0.6),
                              range: NSRange(location: 0, length: showsRemainingLetters ? 0 : session.labelPrefix.utf16.count))
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: frame.midX, yBy: frame.midY)
            transform.rotate(byDegrees: -CGFloat(rotation))
            transform.scaleX(by: min(1, textArea.width / size.width), yBy: 1)
            transform.concat()
            text.draw(at: NSPoint(x: -size.width / 2, y: -size.height / 2))
            NSGraphicsContext.restoreGraphicsState()
        }

        guard session.labelsOnly else { return }
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
