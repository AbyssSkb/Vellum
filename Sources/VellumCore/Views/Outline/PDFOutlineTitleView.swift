@preconcurrency import AppKit
import QuartzCore

final class PDFOutlineTitleView: NSView {
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

    private let marqueeLayer = CATextLayer()
    private weak var observedClipView: NSClipView?
    private var animationDistance: CGFloat?
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
        marqueeLayer.isHidden = true
        layer?.addSublayer(marqueeLayer)
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

    override var intrinsicContentSize: NSSize { textField.intrinsicContentSize }

    override func layout() {
        super.layout()
        updatePresentation()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { updatePresentation(reset: true) }
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
        let size = textField.intrinsicContentSize
        let overflow = ceil(size.width) - bounds.width
        let shouldAnimate = isSelected && overflow > 0 && bounds.width > 0
            && window?.isVisible == true && !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let nextDistance = shouldAnimate ? overflow : nil

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textField.frame = NSRect(
            x: 0, y: floor((bounds.height - size.height) / 2),
            width: bounds.width, height: size.height
        )
        textField.layer?.opacity = shouldAnimate ? 0 : 1
        marqueeLayer.isHidden = !shouldAnimate
        marqueeLayer.contentsScale = window?.backingScaleFactor ?? 2
        if shouldAnimate {
            marqueeLayer.string = NSAttributedString(string: title, attributes: [
                .font: textField.font ?? .systemFont(ofSize: 13),
                .foregroundColor: textField.textColor ?? .labelColor
            ])
            marqueeLayer.frame = NSRect(
                x: 0, y: textField.frame.minY, width: ceil(size.width), height: size.height
            )
        }
        if reset || nextDistance != animationDistance {
            marqueeLayer.removeAnimation(forKey: Self.animationKey)
            marqueeLayer.transform = CATransform3DIdentity
            animationDistance = nextDistance
            if let nextDistance {
                let pause = 1.5
                let travel = max(2, Double(nextDistance) / 30)
                let duration = pause * 2 + travel
                let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
                animation.values = [0, 0, -nextDistance, -nextDistance]
                animation.keyTimes = [0, pause / duration, (pause + travel) / duration, 1]
                    .map { NSNumber(value: $0) }
                animation.duration = duration
                animation.repeatCount = .infinity
                marqueeLayer.add(animation, forKey: Self.animationKey)
            }
        }
        CATransaction.commit()
    }
}
