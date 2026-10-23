import AppKit
import SwiftUI

public enum ToastKind: Equatable, Sendable {
    case info, success, error

    var symbol: String {
        switch self {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }

    var color: NSColor {
        switch self {
        case .info: VellumColors.blue
        case .success: .systemGreen
        case .error: VellumColors.red
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let kind: ToastKind

    init(_ text: String, kind: ToastKind = .info) {
        self.text = text
        self.kind = kind
    }
}

@MainActor
public enum VellumToast {
    public static func show(
        _ message: String,
        kind: ToastKind = .info,
        in window: NSWindow?,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        guard let window, let content = window.contentView, let host = content.superview else { return }
        let currentToasts = host.subviews.compactMap { $0 as? ToastView }
        if action == nil, currentToasts.contains(where: {
            !$0.hasAction && $0.message == message && $0.kind == kind && $0.alphaValue > 0
        }) { return }
        currentToasts.forEach { $0.dismiss(animated: false) }
        let toast = ToastView(message: message, kind: kind, actionTitle: actionTitle, action: action)
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.alphaValue = 0
        // SwiftUI owns its hosting view's child layout; keep the banner beside that content.
        host.addSubview(toast, positioned: .above, relativeTo: content)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            toast.topAnchor.constraint(equalTo: content.topAnchor,
                                       constant: window.styleMask.contains(.fullSizeContentView) ? 58 : 16),
            toast.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 16),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16)
        ])
        host.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            toast.animator().alphaValue = 1
        }
        toast.scheduleDismiss(after: kind == .error ? 5 : 3.2)
        NSAccessibility.post(element: toast, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }
}

extension VellumPDFView {
    func showNotification(_ message: String) {
        showNotification(message, kind: .info)
    }

    func showNotification(_ message: String, kind: ToastKind) {
        VellumToast.show(message, kind: kind, in: window)
    }
}

extension AppState {
    func showNotification(_ message: String) {
        if let activeReaderController {
            activeReaderController.showNotification(message)
        } else {
            showNotification(message, kind: .info)
        }
    }

    func showNotification(_ message: String, kind: ToastKind) {
        guard let readerWindow else {
            pendingNotification = ToastMessage(message, kind: kind)
            return
        }
        VellumToast.show(message, kind: kind, in: readerWindow)
    }

    func showPendingNotification() {
        guard let notification = pendingNotification, let readerWindow else { return }
        pendingNotification = nil
        VellumToast.show(notification.text, kind: notification.kind, in: readerWindow)
    }
}

@MainActor
final class ToastView: NSView {
    let message: String
    let kind: ToastKind
    var hasAction: Bool { action != nil }
    private var dismissalTask: Task<Void, Never>?
    private var action: (() -> Void)?
    private var actionButton: NSButton?

    init(message: String, kind: ToastKind, actionTitle: String?, action: (() -> Void)?) {
        self.message = message
        self.kind = kind
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = (VellumColors.background.blended(withFraction: 0.08, of: kind.color)
                                 ?? VellumColors.background).cgColor
        layer?.cornerCurve = .circular
        layer?.borderWidth = 0.75
        layer?.borderColor = kind.color.withAlphaComponent(0.22).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 12
        layer?.shadowOffset = NSSize(width: 0, height: -4)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(message)
        toolTip = message

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
        icon.contentTintColor = kind.color
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setAccessibilityElement(false)
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = VellumColors.foreground
        label.maximumNumberOfLines = 5
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityElement(false)
        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        ])
        if let actionTitle, action != nil {
            let button = NSButton(title: actionTitle, target: self, action: #selector(performAction))
            button.bezelStyle = .inline
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.contentTintColor = VellumColors.blue
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            addSubview(button)
            actionButton = button
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 12),
                button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
                button.centerYAnchor.constraint(equalTo: centerYAnchor),
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: 28)
            ])
        } else {
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22).isActive = true
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let actionButton, let hit = super.hitTest(point),
              hit === actionButton || hit.isDescendant(of: actionButton) else { return nil }
        return hit
    }

    func scheduleDismiss(after delay: TimeInterval) {
        dismissalTask?.cancel()
        dismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss(animated: Bool = true) {
        dismissalTask?.cancel()
        dismissalTask = nil
        guard animated else { removeFromSuperview(); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in self?.removeFromSuperview() }
        }
    }

    @objc private func performAction() {
        let handler = action
        action = nil
        dismiss(animated: false)
        handler?()
    }

    deinit { dismissalTask?.cancel() }
}

extension View {
    func toast(_ message: ToastMessage?) -> some View {
        background(ToastWindowBridge(message: message).frame(width: 0, height: 0))
    }
}

private struct ToastWindowBridge: NSViewRepresentable {
    let message: ToastMessage?

    func makeNSView(context: Context) -> BridgeView { BridgeView() }

    func updateNSView(_ view: BridgeView, context: Context) {
        view.message = message
        view.presentIfNeeded()
    }

    final class BridgeView: NSView {
        var message: ToastMessage?
        private var presentedID: UUID?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            presentIfNeeded()
        }

        func presentIfNeeded() {
            guard let window, let message, message.id != presentedID else { return }
            presentedID = message.id
            VellumToast.show(message.text, kind: message.kind, in: window)
        }
    }
}
