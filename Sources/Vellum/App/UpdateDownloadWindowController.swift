@preconcurrency import AppKit

@MainActor
final class UpdateDownloadWindowController: NSWindowController {
    var onCancel: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var shouldCancelOnClose = true
    private var lastProgressValue = 0.0

    init(version: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 154),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vellum Update"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        buildContent(version: version)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func updateProgress(receivedBytes: Int64, totalBytes: Int64?) {
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1

        if let totalBytes, totalBytes > 0 {
            let progress = min(1, Double(receivedBytes) / Double(totalBytes))
            updateDeterminateProgress(progress)
            detailLabel.stringValue = "\(Self.formattedPercent(progress)) - \(Self.formattedBytes(receivedBytes)) of \(Self.formattedBytes(totalBytes))"
        } else {
            progressIndicator.isIndeterminate = true
            progressIndicator.startAnimation(nil)
            detailLabel.stringValue = "\(Self.formattedBytes(receivedBytes)) downloaded"
        }
    }

    func updateStatus(_ status: String, detail: String? = nil, indeterminate: Bool = false, canCancel: Bool = true) {
        titleLabel.stringValue = status
        if let detail {
            detailLabel.stringValue = detail
        }
        cancelButton.isEnabled = canCancel
        shouldCancelOnClose = canCancel

        progressIndicator.isIndeterminate = indeterminate
        if indeterminate {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
    }

    func finish() {
        shouldCancelOnClose = false
        window?.close()
    }

    private func buildContent(version: String) {
        guard let contentView = window?.contentView else { return }

        titleLabel.stringValue = "Downloading Vellum \(version)"
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        detailLabel.stringValue = "Preparing download..."
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.lineBreakMode = .byTruncatingMiddle

        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = true
        progressIndicator.controlSize = .large
        progressIndicator.startAnimation(nil)

        cancelButton.target = self
        cancelButton.action = #selector(cancelDownload)
        cancelButton.bezelStyle = .rounded

        let stack = NSStackView(views: [titleLabel, detailLabel, progressIndicator, cancelButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            progressIndicator.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    @objc private func cancelDownload() {
        onCancel?()
    }

    private static func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func updateDeterminateProgress(_ progress: Double) {
        guard abs(progress - lastProgressValue) > 0.0001 || progress >= 1 else { return }
        lastProgressValue = progress

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            progressIndicator.animator().doubleValue = progress
        }
    }

    private static func formattedPercent(_ progress: Double) -> String {
        "\(Int((progress * 100).rounded()))%"
    }
}

extension UpdateDownloadWindowController: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard shouldCancelOnClose else { return }
            onCancel?()
        }
    }
}
