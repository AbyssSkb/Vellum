@preconcurrency import AppKit
import VellumCore

@MainActor
final class UpdateDownloadWindowController: NSWindowController {
    var onCancel: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let progressTrackView = NSView()
    private let progressFillView = NSView()
    private var progressFillWidthConstraint: NSLayoutConstraint?
    private var currentProgressValue = 0.18
    private let language = AppUILanguage.saved()
    private lazy var cancelButton = NSButton(title: language.text(.cancel), target: nil, action: nil)
    private var shouldCancelOnClose = true
    private var lastProgressValue = -1.0

    init(version: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 168),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = AppUILanguage.saved().text(.updateWindowTitle)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = TokyoNight.backgroundDeep
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
        if let totalBytes, totalBytes > 0 {
            let progress = min(1, Double(receivedBytes) / Double(totalBytes))
            updateDeterminateProgress(progress)
            detailLabel.stringValue = "\(Self.formattedPercent(progress)) - \(Self.formattedBytes(receivedBytes)) of \(Self.formattedBytes(totalBytes))"
        } else {
            updateDeterminateProgress(0.18)
            detailLabel.stringValue = language.text(.downloadedBytes(Self.formattedBytes(receivedBytes)))
        }
    }

    func updateStatus(_ status: String, detail: String? = nil, indeterminate: Bool = false, canCancel: Bool = true) {
        titleLabel.stringValue = status
        if let detail {
            detailLabel.stringValue = detail
        }
        cancelButton.isEnabled = canCancel
        shouldCancelOnClose = canCancel
        updateDeterminateProgress(indeterminate ? 0.18 : lastProgressValue)
    }

    func finish() {
        shouldCancelOnClose = false
        window?.close()
    }

    private func buildContent(version: String) {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = TokyoNight.backgroundDeep.cgColor

        let iconWell = NSView()
        iconWell.translatesAutoresizingMaskIntoConstraints = false
        iconWell.wantsLayer = true
        iconWell.layer?.backgroundColor = TokyoNight.panelElevated.cgColor
        iconWell.layer?.cornerRadius = 8
        iconWell.layer?.borderWidth = 1
        iconWell.layer?.borderColor = TokyoNight.border.cgColor

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
        iconView.contentTintColor = TokyoNight.cyan
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconWell.addSubview(iconView)

        titleLabel.stringValue = language.text(.downloadingVersion(version))
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = TokyoNight.foreground
        titleLabel.lineBreakMode = .byTruncatingTail

        detailLabel.stringValue = language.text(.preparingDownload)
        detailLabel.textColor = TokyoNight.muted
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.lineBreakMode = .byTruncatingMiddle

        let labelStack = NSStackView(views: [titleLabel, detailLabel])
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 5

        let headerStack = NSStackView(views: [iconWell, labelStack])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 12

        progressTrackView.translatesAutoresizingMaskIntoConstraints = false
        progressTrackView.wantsLayer = true
        progressTrackView.layer?.backgroundColor = TokyoNight.background.cgColor
        progressTrackView.layer?.cornerRadius = 4
        progressTrackView.layer?.borderWidth = 1
        progressTrackView.layer?.borderColor = TokyoNight.border.cgColor

        progressFillView.translatesAutoresizingMaskIntoConstraints = false
        progressFillView.wantsLayer = true
        progressFillView.layer?.backgroundColor = TokyoNight.blue.cgColor
        progressFillView.layer?.cornerRadius = 3
        progressTrackView.addSubview(progressFillView)

        cancelButton.target = self
        cancelButton.action = #selector(cancelDownload)
        cancelButton.isBordered = false
        cancelButton.controlSize = .regular
        cancelButton.font = .systemFont(ofSize: 12, weight: .semibold)
        cancelButton.contentTintColor = TokyoNight.foreground
        cancelButton.wantsLayer = true
        cancelButton.layer?.backgroundColor = TokyoNight.panelElevated.cgColor
        cancelButton.layer?.cornerRadius = 6
        cancelButton.layer?.borderWidth = 1
        cancelButton.layer?.borderColor = TokyoNight.border.cgColor
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)

        let actionSpacer = NSView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let actionStack = NSStackView(views: [actionSpacer, cancelButton])
        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.distribution = .fill
        actionStack.spacing = 0

        let stack = NSStackView(views: [headerStack, progressTrackView, actionStack])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        progressFillWidthConstraint = progressFillView.widthAnchor.constraint(equalToConstant: 0)
        progressFillWidthConstraint?.isActive = true
        NSLayoutConstraint.activate([
            iconWell.widthAnchor.constraint(equalToConstant: 36),
            iconWell.heightAnchor.constraint(equalToConstant: 36),
            iconView.centerXAnchor.constraint(equalTo: iconWell.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            titleLabel.widthAnchor.constraint(equalTo: labelStack.widthAnchor),
            detailLabel.widthAnchor.constraint(equalTo: labelStack.widthAnchor),
            progressTrackView.heightAnchor.constraint(equalToConstant: 10),
            progressFillView.leadingAnchor.constraint(equalTo: progressTrackView.leadingAnchor, constant: 2),
            progressFillView.topAnchor.constraint(equalTo: progressTrackView.topAnchor, constant: 2),
            progressFillView.bottomAnchor.constraint(equalTo: progressTrackView.bottomAnchor, constant: -2),
            progressFillView.widthAnchor.constraint(lessThanOrEqualTo: progressTrackView.widthAnchor, constant: -4),
            cancelButton.heightAnchor.constraint(equalToConstant: 28),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 44),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
        DispatchQueue.main.async { [weak self] in
            self?.applyProgressFillWidth(animated: false)
        }
    }

    @objc private func cancelDownload() {
        onCancel?()
    }

    private static func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func updateDeterminateProgress(_ progress: Double) {
        guard abs(progress - lastProgressValue) > 0.0001 || progress >= 1 else { return }
        currentProgressValue = min(max(progress, 0), 1)
        applyProgressFillWidth(animated: true)
    }

    private func applyProgressFillWidth(animated: Bool) {
        progressTrackView.superview?.layoutSubtreeIfNeeded()
        let fillWidth = max(0, progressTrackView.bounds.width - 4) * CGFloat(currentProgressValue)
        lastProgressValue = currentProgressValue

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.12 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            progressFillWidthConstraint?.animator().constant = fillWidth
            progressTrackView.layoutSubtreeIfNeeded()
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
