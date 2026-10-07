@preconcurrency import AppKit
import QuartzCore

final class PDFOutlineTitleView: NSView, CAAnimationDelegate {
    let textField = NSTextField(labelWithString: "")
    var title = "" {
        didSet {
            textField.stringValue = title
            toolTip = title
            textField.toolTip = title
            invalidateIntrinsicContentSize()
            updatePresentation(reset: true)
        }
    }
    var isSelected = false {
        didSet {
            invalidateIntrinsicContentSize()
            updatePresentation(reset: true)
        }
    }
    var repeatsMarquee = true

    private weak var observedClipView: NSClipView?
    private var animationDistance: CGFloat?
    private var singlePlaybackPending = false
    private var singlePlaybackGeneration = 0
    private static let animationKey = "outlineTitleScroll"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
        wantsLayer = true
        layer?.masksToBounds = true
        textField.wantsLayer = true
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byTruncatingTail
        textField.font = .systemFont(ofSize: 13)
        addSubview(textField)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(presentationChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(presentationChanged),
            name: NSWindow.didChangeOcclusionStateNotification, object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        textField.frame(forAlignmentRect: NSRect(origin: .zero, size: textField.intrinsicContentSize)).size
    }

    func playMarqueeOnce() {
        singlePlaybackPending = true
        singlePlaybackGeneration += 1
        if isSelected {
            updatePresentation(reset: true)
        } else {
            isSelected = true
        }
    }

    func stopMarquee() {
        singlePlaybackPending = false
        singlePlaybackGeneration += 1
        isSelected = false
    }

    nonisolated func animationDidStop(_ animation: CAAnimation, finished: Bool) {
        guard finished else { return }
        let generation = animation.value(forKey: "singlePlaybackGeneration") as? Int
        MainActor.assumeIsolated {
            guard !repeatsMarquee, generation == singlePlaybackGeneration else { return }
            stopMarquee()
        }
    }

    override func layout() {
        super.layout()
        updatePresentation()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { updatePresentation(reset: repeatsMarquee) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observedClipView {
            NotificationCenter.default.removeObserver(
                self, name: NSView.boundsDidChangeNotification, object: observedClipView
            )
        }
        observedClipView = enclosingScrollView?.contentView
        if let observedClipView {
            observedClipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(presentationChanged),
                name: NSView.boundsDidChangeNotification, object: observedClipView
            )
        }
        updatePresentation(reset: true)
    }

    override func viewDidHide() {
        super.viewDidHide()
        updatePresentation()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updatePresentation()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updatePresentation()
    }

    @objc private func presentationChanged(_ notification: Notification) {
        if let changedWindow = notification.object as? NSWindow, changedWindow !== window { return }
        updatePresentation()
    }

    private func updatePresentation(reset: Bool = false) {
        let size = intrinsicContentSize
        let overflow = ceil(size.width) - bounds.width
        let reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reducesMotion || (bounds.width > 0 && overflow <= 0) { singlePlaybackPending = false }
        let continuingSinglePlayback = animationDistance == overflow && !reset
        let shouldAnimate = isSelected && overflow > 0 && bounds.width > 0
            && window?.isVisible == true && !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty
            && !reducesMotion && (repeatsMarquee || singlePlaybackPending || continuingSinglePlayback)
        let nextDistance = shouldAnimate ? overflow : nil

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textField.frame = NSRect(
            x: 0, y: floor((bounds.height - size.height) / 2),
            width: shouldAnimate ? ceil(size.width) : bounds.width, height: size.height
        )
        if reset || nextDistance != animationDistance {
            textField.layer?.removeAnimation(forKey: Self.animationKey)
            textField.layer?.transform = CATransform3DIdentity
            animationDistance = nextDistance
            if let nextDistance {
                let pause = 1.5
                let travel = Double(nextDistance) / 30
                let duration = pause * 2 + travel
                let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
                animation.values = [0, 0, -nextDistance, -nextDistance]
                animation.keyTimes = [0, pause / duration, (pause + travel) / duration, 1]
                    .map { NSNumber(value: $0) }
                animation.calculationMode = .linear
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
                animation.duration = duration
                animation.repeatCount = repeatsMarquee ? .infinity : 0
                if !repeatsMarquee {
                    singlePlaybackPending = false
                    animation.setValue(singlePlaybackGeneration, forKey: "singlePlaybackGeneration")
                    animation.delegate = self
                }
                textField.layer?.add(animation, forKey: Self.animationKey)
            }
        }
        CATransaction.commit()
    }
}
