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
        cancelPageOverview()

        let pageIndex = currentVisiblePageIndex(in: document)
        let overlay = PageOverviewOverlayView(
            document: document,
            selectedIndex: pageIndex,
            columns: Self.pageOverviewColumns,
            entryPageRect: document.page(at: pageIndex).flatMap {
                viewRect(for: $0.bounds(for: displayBox), on: $0)
            }
        )
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]

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
        guard let pageOverviewController, let document else { return }
        let selectedIndex = pageOverviewController.selectedIndex
        let originalIndex = pageOverviewController.originalIndex
        let overlay = pageOverviewController.overlay
        self.pageOverviewController = nil
        cancelPendingRestore()
        if selectedIndex != originalIndex { vimGoToPage(selectedIndex + 1) }
        let generation = restoreGeneration
        // PDFKit repeats page navigation on the next turn; measure its settled position.
        DispatchQueue.main.async { [weak self] in
            guard let self, overlay.superview === self, self.document === document,
                  self.restoreGeneration == generation else {
                overlay.dismiss(animated: false)
                return
            }
            self.layoutSubtreeIfNeeded()
            let rect = document.page(at: selectedIndex).flatMap {
                self.viewRect(for: $0.bounds(for: self.displayBox), on: $0)
            }
            overlay.dismiss(to: rect)
        }
    }

    func cancelPageOverview() {
        pageOverviewController = nil
        for overlay in subviews.compactMap({ $0 as? PageOverviewOverlayView }) {
            overlay.dismiss(animated: false)
        }
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

}

@MainActor
final class PageOverviewOverlayView: NSView {
    var onSelectPage: ((Int) -> Void)?

    private let document: PDFDocument
    private let visibleCount: Int
    private var selectedIndex: Int
    private var visibleIndexes: [Int] = []
    private let thumbnails: PageOverviewThumbnailLoader
    private let backdrop = CALayer()
    private var entryPageRect: NSRect?
    private var presented = false
    private var papers: [Int: CALayer] = [:]
    private let positionLabel = NSTextField(labelWithString: "")
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private(set) var dismissed = false
    private var transitionGeneration = 0
    private static let transitionKey = "galleryTransition"
    private var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(document: PDFDocument, selectedIndex: Int, columns: Int, entryPageRect: NSRect? = nil,
         thumbnailLoader: PageOverviewThumbnailLoader? = nil) {
        self.document = document
        self.selectedIndex = selectedIndex
        self.visibleCount = columns
        self.entryPageRect = entryPageRect
        self.thumbnails = thumbnailLoader ?? PageOverviewThumbnailLoader()
        super.init(frame: .zero)
        wantsLayer = true
        alphaValue = 0
        backdrop.backgroundColor = TokyoNight.panel.cgColor
        backdrop.opacity = 0
        backdrop.zPosition = -1
        layer?.addSublayer(backdrop)
        layer?.masksToBounds = true
        setAccessibilityRole(.group)
        setAccessibilityLabel(AppUILanguage.saved().text(.pageOverview))
        positionLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        positionLabel.textColor = TokyoNight.muted
        positionLabel.alignment = .center
        positionLabel.alphaValue = 0
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
            button.alphaValue = 0
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
        if !presented { entryPageRect = nil }
        self.selectedIndex = selectedIndex
        updateVisibleIndexes()
        layoutPapers(animated: true, enteringFrom: previousIndex)
        updateThumbnails()
    }

    func dismiss(animated: Bool = true, to pageRect: NSRect? = nil) {
        if !animated {
            dismissed = true
            thumbnails.cancel()
            removeFromSuperview()
            return
        }
        guard !dismissed else { return }
        dismissed = true
        thumbnails.cancel()
        guard presented, !reducesMotion, window?.isVisible == true else {
            removeFromSuperview()
            return
        }
        guard let pageRect, !pageRect.isEmpty, let selectedPaper = papers[selectedIndex],
              selectedPaper.sublayers?.first?.contents != nil,
              paperSize(for: selectedIndex).width > 0 else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.removeFromSuperview() }
            })
            return
        }

        let movementDuration = 0.28
        let duration = movementDuration + 0.06
        let scale = pageRect.width / paperSize(for: selectedIndex).width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, paper) in papers {
            let current = paper.presentation() ?? paper
            let fromPosition = current.position
            let fromTransform = current.transform
            let fromOpacity = current.opacity
            let fromShadow = current.shadowRadius
            paper.position = fromPosition
            paper.transform = fromTransform
            paper.removeAnimation(forKey: Self.transitionKey)
            if index == selectedIndex {
                paper.position = CGPoint(x: pageRect.midX, y: pageRect.midY - 14 * scale)
                paper.transform = CATransform3DMakeScale(scale, scale, 1)
                paper.opacity = 1
                paper.shadowRadius = 4
                paper.zPosition = 3
                addTransition(to: paper, values: [
                    ("position", NSValue(point: fromPosition), NSValue(point: paper.position)),
                    ("transform", NSValue(caTransform3D: fromTransform), NSValue(caTransform3D: paper.transform)),
                    ("opacity", fromOpacity, paper.opacity),
                    ("shadowRadius", fromShadow, paper.shadowRadius)
                ], duration: movementDuration, entering: true)
            } else {
                paper.opacity = 0
                addTransition(to: paper, values: [("opacity", fromOpacity, Float(0))], duration: 0.18)
            }
            let number = paper.sublayers![1]
            let shade = paper.sublayers![0].sublayers![0]
            for detail in [number, shade] {
                let from = detail.presentation()?.opacity ?? detail.opacity
                detail.opacity = 0
                addTransition(to: detail, values: [("opacity", from, Float(0))], duration: 0.14)
            }
        }
        let fromBackdrop = backdrop.presentation()?.opacity ?? backdrop.opacity
        backdrop.opacity = 1
        addTransition(to: backdrop, values: [("opacity", fromBackdrop, Float(1))], duration: 0.08)
        // Hand the matching paper back to PDFKit only at the end of its expansion.
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, NSNumber(value: movementDuration / duration), 1]
        fade.duration = duration
        layer?.opacity = 0
        layer?.add(fade, forKey: "galleryExitFade")
        CATransaction.commit()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            positionLabel.animator().alphaValue = 0
            previousButton.animator().alphaValue = 0
            nextButton.animator().alphaValue = 0
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.removeFromSuperview()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        if dismissed, newSize != frame.size { dismiss(animated: false) }
        if window != nil, newSize != frame.size { entryPageRect = nil }
        super.setFrameSize(newSize)
        layoutPapers(animated: false)
        updateThumbnails()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !dismissed else { return }
        layoutPapers(animated: false)
        updateThumbnails()
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
        let shade = CALayer()
        shade.name = "shade"
        shade.backgroundColor = TokyoNight.panel.cgColor
        image.addSublayer(shade)
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
        // Keep the previous paper in place until the requested page can replace it.
        guard !presented || thumbnails.images[selectedIndex] != nil else { return }
        transitionGeneration += 1
        let generation = transitionGeneration
        let startsEntry = !presented && thumbnails.images[selectedIndex] != nil
        let sourceRect = startsEntry ? entryPageRect : nil
        let duration = sourceRect == nil ? 0.26 : 0.34
        let animate = (animated || startsEntry) && !reducesMotion && window?.isVisible == true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds
        if startsEntry {
            presented = true
            entryPageRect = nil
            alphaValue = 1
            backdrop.opacity = 1
            if animate {
                addTransition(to: backdrop, values: [("opacity", Float(0), Float(1))], duration: 0.16)
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animate ? 0.24 : 0
                positionLabel.animator().alphaValue = 1
                previousButton.animator().alphaValue = 1
                nextButton.animator().alphaValue = 1
            }
        }
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
            let shade = image.sublayers![0]
            if let sourceRect, index == selectedIndex, size.width > 0 {
                let scale = sourceRect.width / size.width
                paper.position = CGPoint(x: sourceRect.midX, y: sourceRect.midY - 14 * scale)
                paper.transform = CATransform3DMakeScale(scale, scale, 1)
                paper.opacity = 1
                paper.shadowRadius = 4
            }
            let current = sourceRect != nil && index == selectedIndex ? paper : (paper.presentation() ?? paper)
            let fromPosition = current.position
            let fromTransform = current.transform
            let fromOpacity = current.opacity
            let fromShadow = current.shadowRadius
            let fromNumberOpacity = number.presentation()?.opacity ?? number.opacity
            let fromShadeOpacity = shade.presentation()?.opacity ?? shade.opacity
            paper.bounds = CGRect(origin: .zero, size: NSSize(width: size.width, height: size.height + 28))
            image.frame = CGRect(x: 0, y: 28, width: size.width, height: size.height)
            image.contentsScale = window?.backingScaleFactor ?? 2
            if let thumbnail = thumbnails.images[index] {
                image.contents = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
            number.frame = CGRect(x: 0, y: 2, width: size.width, height: 20)
            number.contentsScale = image.contentsScale
            let numberOpacity: Float = index == selectedIndex ? 0 : 1
            let shadeOpacity: Float = index == selectedIndex ? 0 : 0.13
            let shadowRadius: CGFloat = index == selectedIndex ? 22 : 16
            let detailChanged = number.opacity != numberOpacity || shade.opacity != shadeOpacity
                || paper.shadowRadius != shadowRadius
            number.opacity = numberOpacity
            shade.frame = image.bounds
            shade.opacity = shadeOpacity
            paper.shadowPath = CGPath(roundedRect: image.frame, cornerWidth: 2, cornerHeight: 2, transform: nil)
            paper.shadowRadius = shadowRadius
            let targetPosition = position(for: index, selectedIndex: selectedIndex)
            let targetTransform = transform(for: index, selectedIndex: selectedIndex)
            let targetOpacity: Float = visible && image.contents != nil ? 1 : 0
            let targetZ: CGFloat = index == selectedIndex ? 3 : 1
            let changed = paper.position != targetPosition || !CATransform3DEqualToTransform(paper.transform, targetTransform)
                || paper.opacity != targetOpacity || detailChanged
            paper.position = targetPosition
            paper.transform = targetTransform
            paper.opacity = targetOpacity
            paper.zPosition = targetZ
            if animate && changed {
                let values: [(String, Any, Any)] = [
                    ("position", NSValue(point: fromPosition), NSValue(point: paper.position)),
                    ("transform", NSValue(caTransform3D: fromTransform), NSValue(caTransform3D: paper.transform)),
                    ("opacity", fromOpacity, paper.opacity),
                    ("shadowRadius", fromShadow, paper.shadowRadius)
                ]
                addTransition(to: paper, values: values, duration: duration, entering: sourceRect != nil)
                addTransition(to: number, values: [("opacity", fromNumberOpacity, number.opacity)], duration: duration, entering: sourceRect != nil)
                addTransition(to: shade, values: [("opacity", fromShadeOpacity, shade.opacity)], duration: duration, entering: sourceRect != nil)
            } else if !animate {
                paper.removeAnimation(forKey: Self.transitionKey)
                number.removeAnimation(forKey: Self.transitionKey)
                shade.removeAnimation(forKey: Self.transitionKey)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) { [weak self] in
                self?.removeDepartedPapers(completedThrough: generation)
            }
        } else {
            removeDepartedPapers()
        }
    }

    private func addTransition(to layer: CALayer, values: [(String, Any, Any)], duration: TimeInterval, entering: Bool = false) {
        let group = CAAnimationGroup()
        group.animations = values.map { key, from, to in
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = from
            animation.toValue = to
            return animation
        }
        group.setValue(transitionGeneration, forKey: "galleryGeneration")
        group.duration = duration
        group.timingFunction = entering ? CAMediaTimingFunction(name: .easeInEaseOut)
            : CAMediaTimingFunction(controlPoints: 0.22, 0.7, 0.22, 1)
        layer.add(group, forKey: Self.transitionKey)
    }

    private func removeDepartedPapers(completedThrough generation: Int = .max) {
        guard !dismissed else { return }
        guard thumbnails.images[selectedIndex] != nil else { return }
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
        var sizes = visibleIndexes.map { paperSize(for: $0) }
        if let entryPageRect {
            // ponytail: cap the entry raster at two viewports; use tiles for deeper zoom detail.
            let limit = max(bounds.width, bounds.height) * 2
            sizes.append(NSSize(width: min(entryPageRect.width, limit), height: min(entryPageRect.height, limit)))
        }
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
