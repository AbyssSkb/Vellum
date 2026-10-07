@preconcurrency import AppKit
import PDFKit
import QuartzCore

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

        pageOverviewController?.dismiss(animated: false)
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

        guard selectedIndex != originalIndex else { return }

        vimGoToPage(selectedIndex + 1)
    }

    func cancelPageOverview() {
        pageOverviewController?.dismiss(animated: false)
        pageOverviewController = nil
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
        overlay.onSelectPage = { [weak self] in self?.select($0) }
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

        select(selectedIndex + delta)
    }

    private func select(_ index: Int) {
        let nextIndex = min(max(index, 0), pageCount - 1)
        guard nextIndex != selectedIndex else { return }

        selectedIndex = nextIndex
        overlay.update(selectedIndex: selectedIndex)
    }

    func dismiss(animated: Bool = true) {
        overlay.dismiss(animated: animated)
    }
}

@MainActor
final class PageOverviewOverlayView: NSView {
    var onSelectPage: ((Int) -> Void)?

    private let document: PDFDocument
    private let visibleCount: Int
    private var selectedIndex: Int
    private var visibleIndexes: [Int] = []
    private let thumbnails = PageOverviewThumbnailLoader()
    private var papers: [Int: CALayer] = [:]
    private let positionLabel = NSTextField(labelWithString: "")
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private var dismissed = false
    private var transitionGeneration = 0
    private static let transitionKey = "galleryTransition"
    private var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(document: PDFDocument, selectedIndex: Int, columns: Int) {
        self.document = document
        self.selectedIndex = selectedIndex
        self.visibleCount = columns
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = TokyoNight.panel.cgColor
        layer?.masksToBounds = true
        setAccessibilityRole(.group)
        setAccessibilityLabel(AppUILanguage.saved().text(.pageOverview))
        positionLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        positionLabel.textColor = TokyoNight.muted
        positionLabel.alignment = .center
        addSubview(positionLabel)
        for (button, symbol, action) in [
            (previousButton, "chevron.left", #selector(previousPage)),
            (nextButton, "chevron.right", #selector(nextPage))
        ] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            button.isBordered = false
            button.refusesFirstResponder = true
            button.contentTintColor = TokyoNight.muted
            button.target = self
            button.action = action
            addSubview(button)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
        updateVisibleIndexes()
    }

    required init?(coder: NSCoder) { nil }

    func update(selectedIndex: Int) {
        guard !dismissed else { return }
        let previousIndex = self.selectedIndex
        self.selectedIndex = selectedIndex
        updateVisibleIndexes()
        layoutPapers(animated: true, enteringFrom: previousIndex)
        updateThumbnails()
    }

    func dismiss(animated: Bool = true) {
        guard !dismissed else { return }
        dismissed = true
        thumbnails.cancel()
        guard animated, !reducesMotion, window != nil else {
            removeFromSuperview()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.removeFromSuperview() }
        })
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutPapers(animated: false)
        updateThumbnails()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !dismissed else { return }
        layoutPapers(animated: false)
        updateThumbnails()
        guard !reducesMotion else { return }
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            animator().alphaValue = 1
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layoutPapers(animated: false)
        updateThumbnails()
    }

    override func mouseDown(with event: NSEvent) {
        guard !dismissed else { return }
        let point = convert(event.locationInWindow, from: nil)
        var hit = layer?.presentation()?.hitTest(point) ?? layer?.hitTest(point)
        while let candidate = hit {
            if let name = candidate.name, name.hasPrefix("page-"),
               let index = Int(name.dropFirst(5)), visibleIndexes.contains(index) {
                onSelectPage?(index)
                return
            }
            hit = candidate.superlayer
        }
    }

    @objc private func previousPage() { onSelectPage?(selectedIndex - 1) }
    @objc private func nextPage() { onSelectPage?(selectedIndex + 1) }
    @objc private func displayOptionsChanged() { layoutPapers(animated: false) }

    private func updateVisibleIndexes() {
        visibleIndexes = PageOverviewWindow.slots(
            selectedIndex: selectedIndex, pageCount: document.pageCount, visibleCount: visibleCount
        ).compactMap(\.self)
    }

    // Each neighbor is rendered at its full, unscaled size so promotion stays crisp.
    func paperSize(for index: Int) -> NSSize {
        guard let page = document.page(at: index) else { return .zero }
        let size = PDFPageDisplayGeometry(page: page, box: .cropBox).bounds.size
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(max(1, bounds.width - 48) * 0.78 / size.width,
                        max(1, bounds.height - 104) / size.height)
        return NSSize(width: size.width * scale, height: size.height * scale)
    }

    private func makePaper(index: Int) -> CALayer {
        let paper = CALayer()
        paper.name = "page-\(index)"
        paper.shadowColor = NSColor.black.cgColor
        paper.shadowOpacity = 0.35
        paper.shadowOffset = CGSize(width: 0, height: -10)
        let image = CALayer()
        image.name = "thumbnail"
        image.backgroundColor = NSColor.white.cgColor
        image.cornerRadius = 2
        image.masksToBounds = true
        image.contentsGravity = .resizeAspect
        paper.addSublayer(image)
        let number = CATextLayer()
        number.string = "\(index + 1)"
        number.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        number.fontSize = 11
        number.foregroundColor = TokyoNight.muted.cgColor
        number.alignmentMode = .center
        paper.addSublayer(number)
        layer?.addSublayer(paper)
        return paper
    }

    private func layoutPapers(animated: Bool, enteringFrom previousIndex: Int? = nil) {
        guard !dismissed, bounds.width > 24, bounds.height > 24 else { return }
        transitionGeneration += 1
        let generation = transitionGeneration
        let animate = animated && !reducesMotion && window?.isVisible == true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in visibleIndexes where papers[index] == nil {
            let paper = makePaper(index: index)
            paper.position = position(for: index, selectedIndex: previousIndex ?? selectedIndex)
            paper.transform = transform(for: index, selectedIndex: previousIndex ?? selectedIndex)
            paper.opacity = 0
            papers[index] = paper
        }
        for (index, paper) in papers {
            let visible = visibleIndexes.contains(index)
            let size = paperSize(for: index)
            let image = paper.sublayers![0]
            let number = paper.sublayers![1]
            let current = paper.presentation() ?? paper
            let fromPosition = current.position
            let fromTransform = current.transform
            let fromOpacity = current.opacity
            let fromZ = current.zPosition
            paper.bounds = CGRect(origin: .zero, size: NSSize(width: size.width, height: size.height + 28))
            image.frame = CGRect(x: 0, y: 28, width: size.width, height: size.height)
            image.contentsScale = window?.backingScaleFactor ?? 2
            if let thumbnail = thumbnails.images[index] {
                image.contents = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
            number.frame = CGRect(x: 0, y: 2, width: size.width, height: 20)
            number.contentsScale = image.contentsScale
            number.opacity = index == selectedIndex ? 0 : 1
            paper.shadowPath = CGPath(roundedRect: image.frame, cornerWidth: 2, cornerHeight: 2, transform: nil)
            paper.shadowRadius = index == selectedIndex ? 22 : 16
            let targetPosition = position(for: index, selectedIndex: selectedIndex)
            let targetTransform = transform(for: index, selectedIndex: selectedIndex)
            let targetOpacity: Float = visible && image.contents != nil ? (index == selectedIndex ? 1 : 0.87) : 0
            let targetZ: CGFloat = index == selectedIndex ? 3 : 1
            let changed = paper.position != targetPosition || !CATransform3DEqualToTransform(paper.transform, targetTransform)
                || paper.opacity != targetOpacity || paper.zPosition != targetZ
            paper.position = targetPosition
            paper.transform = targetTransform
            paper.opacity = targetOpacity
            paper.zPosition = targetZ
            if animate && changed {
                let values: [(String, Any, Any)] = [
                    ("position", NSValue(point: fromPosition), NSValue(point: paper.position)),
                    ("transform", NSValue(caTransform3D: fromTransform), NSValue(caTransform3D: paper.transform)),
                    ("opacity", fromOpacity, paper.opacity),
                    ("zPosition", fromZ, paper.zPosition)
                ]
                let group = CAAnimationGroup()
                group.animations = values.map { key, from, to in
                    let animation = CABasicAnimation(keyPath: key)
                    animation.fromValue = from
                    animation.toValue = to
                    return animation
                }
                group.setValue(generation, forKey: "galleryGeneration")
                group.duration = 0.22
                group.timingFunction = CAMediaTimingFunction(name: .easeOut)
                paper.add(group, forKey: Self.transitionKey)
            } else if !animate {
                paper.removeAnimation(forKey: Self.transitionKey)
            }
        }
        positionLabel.stringValue = "\(selectedIndex + 1)  /  \(document.pageCount)"
        positionLabel.setAccessibilityLabel(AppUILanguage.saved().text(.pageOverviewPosition(selectedIndex + 1, document.pageCount)))
        positionLabel.frame = NSRect(x: bounds.midX - 46, y: 24, width: 92, height: 20)
        previousButton.frame = NSRect(x: bounds.midX - 94, y: 16, width: 36, height: 36)
        nextButton.frame = NSRect(x: bounds.midX + 58, y: 16, width: 36, height: 36)
        previousButton.isEnabled = selectedIndex > 0
        nextButton.isEnabled = selectedIndex + 1 < document.pageCount
        previousButton.setAccessibilityLabel(AppUILanguage.saved().text(.pageOverviewPosition(max(1, selectedIndex), document.pageCount)))
        nextButton.setAccessibilityLabel(AppUILanguage.saved().text(.pageOverviewPosition(min(document.pageCount, selectedIndex + 2), document.pageCount)))
        CATransaction.commit()
        if animate {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
                self?.removeDepartedPapers(completedThrough: generation)
            }
        } else {
            removeDepartedPapers()
        }
    }

    private func removeDepartedPapers(completedThrough generation: Int = .max) {
        for index in Array(papers.keys) where !visibleIndexes.contains(index) {
            let animation = papers[index]?.animation(forKey: Self.transitionKey)
            guard (animation?.value(forKey: "galleryGeneration") as? Int ?? 0) <= generation else { continue }
            papers.removeValue(forKey: index)?.removeFromSuperlayer()
        }
    }

    private func position(for index: Int, selectedIndex: Int) -> CGPoint {
        let offset = CGFloat(min(max(index - selectedIndex, -2), 2))
        return CGPoint(x: bounds.midX + offset * bounds.width * 0.31,
                       y: bounds.midY + 14 - (offset == 0 ? 0 : 38))
    }

    private func transform(for index: Int, selectedIndex: Int) -> CATransform3D {
        guard index != selectedIndex else { return CATransform3DIdentity }
        let angle: CGFloat = index < selectedIndex ? 0.042 : -0.042
        return CATransform3DRotate(CATransform3DMakeScale(0.84, 0.84, 1), angle, 0, 0, 1)
    }

    private func updateThumbnails() {
        guard !dismissed, let window, bounds.width > 24, bounds.height > 24 else { return }
        let sizes = visibleIndexes.map { paperSize(for: $0) }
        let scale = window.backingScaleFactor
        thumbnails.update(
            document: document,
            pageIndexes: [selectedIndex] + visibleIndexes.filter { $0 != selectedIndex },
            selectedIndex: selectedIndex,
            maximumPixelSize: NSSize(width: (sizes.map(\.width).max() ?? 1) * scale,
                                     height: (sizes.map(\.height).max() ?? 1) * scale)
        ) { [weak self] in
            self?.layoutPapers(animated: true)
        }
    }
}
