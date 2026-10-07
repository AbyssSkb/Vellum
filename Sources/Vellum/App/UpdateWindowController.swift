@preconcurrency import AppKit
import VellumCore

struct UpdateWindowContent {
    enum Phase: Equatable {
        case checking, upToDate, available, downloading, extracting, ready, installing, error
    }

    var phase: Phase
    var currentVersion: String
    var updateVersion: String? = nil
    var releaseNotes: [AppReleaseNotesSection] = []
    var message: String? = nil
    var progress: Double? = nil
    var actions: [UpdateWindowAction] = []
}

struct UpdateWindowAction {
    var title: String
    var key: String
    var isPrimary: Bool = false
    var handler: () -> Void
}

@MainActor
final class UpdateWindowController: NSWindowController {
    var onClose: (() -> Void)?

    private var content: UpdateWindowContent?
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let versionsLabel = NSTextField(labelWithString: "")
    private let notesTitle = NSTextField(labelWithString: "")
    private let notesScrollView = NSScrollView()
    private let notesView = NSTextView()
    private let progressTrack = NSView()
    private let progressFill = NSView()
    private let footer = NSStackView()
    private let header = UpdateDragRegion()
    private let footerBackground = NSView()
    private let divider = NSView()
    private var standardStatusConstraints: [NSLayoutConstraint] = []
    private var compactStatusConstraints: [NSLayoutConstraint] = []
    private var compactStatus = false
    private var contentWidth: NSLayoutConstraint?
    private var progressWidth: NSLayoutConstraint?
    private var notesBottom: NSLayoutConstraint?
    private var notesCollapsedHeight: NSLayoutConstraint?
    private var buttons: [UpdateActionButton] = []
    private var didNotifyClose = false
    private var count = ""
    private var pendingG = false

    init() {
        let window = UpdatePanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = AppUILanguage.saved().text(.updateWindowTitle)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = TokyoNight.background
        window.isReleasedWhenClosed = false
        window.contentView = UpdateContentView(frame: NSRect(x: 0, y: 0, width: 560, height: 500))
        super.init(window: window)
        window.delegate = self
        window.handleKey = { [weak self] in self?.handleKey($0) ?? false }
        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    func present(_ content: UpdateWindowContent, activate: Bool = true) {
        didNotifyClose = false
        clearPendingInput()
        update(content)
        if window?.isVisible != true { window?.center() }
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.orderFront(nil)
        }
    }

    func update(_ content: UpdateWindowContent) {
        let previous = self.content
        self.content = content
        let language = AppUILanguage.saved()
        let version = content.updateVersion ?? content.currentVersion
        let title: AppText
        let symbol: String
        switch content.phase {
        case .checking: title = .checkingForUpdates; symbol = "arrow.triangle.2.circlepath"
        case .upToDate: title = .upToDate; symbol = "checkmark.circle"
        case .available: title = .updateAvailableTitle(version); symbol = "arrow.down.circle"
        case .downloading: title = .downloadingVersion(version); symbol = "arrow.down.circle"
        case .extracting: title = .extractingUpdate; symbol = "shippingbox"
        case .ready: title = .updateReadyTitle(version); symbol = "checkmark.circle"
        case .installing: title = .installingVersion(version); symbol = "arrow.triangle.2.circlepath"
        case .error: title = .updateError; symbol = "exclamationmark.circle"
        }
        titleLabel.stringValue = language.text(title)
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        iconView.contentTintColor = content.phase == .error ? TokyoNight.red
            : content.phase == .upToDate ? .systemGreen : TokyoNight.muted
        detailLabel.stringValue = content.phase == .error ? "" : content.message ?? (content.phase == .ready
            ? language.text(.updateReadyInstallDetail(current: content.currentVersion))
            : content.phase == .installing ? language.text(.installingDetail) : "")
        versionsLabel.stringValue = "\(language.text(.currentVersion))  \(content.currentVersion)"
            + (content.updateVersion.map { "     →     \(language.text(.updateNewVersion))  \($0)" } ?? "")
        let errorMessage = content.phase == .error ? content.message : nil
        notesTitle.stringValue = language.text(errorMessage == nil ? .whatsNew : .updateDetails)

        let previousError = previous?.phase == .error ? previous?.message : nil
        if previous?.releaseNotes != content.releaseNotes || previousError != errorMessage {
            let body = errorMessage.map { NSAttributedString(string: $0, attributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: TokyoNight.foreground
            ]) } ?? attributedReleaseNotes(content.releaseNotes)
            notesView.textStorage?.setAttributedString(body)
            notesScrollView.contentView.scroll(to: .zero)
            notesScrollView.reflectScrolledClipView(notesScrollView.contentView)
        }
        let hasBody = !content.releaseNotes.isEmpty || errorMessage?.isEmpty == false
        let wasCompact = compactStatus
        compactStatus = !hasBody && [.checking, .upToDate].contains(content.phase)
        if wasCompact != compactStatus {
            NSLayoutConstraint.deactivate(compactStatus ? standardStatusConstraints : compactStatusConstraints)
            NSLayoutConstraint.activate(compactStatus ? compactStatusConstraints : standardStatusConstraints)
        }
        titleLabel.alignment = compactStatus ? .center : .left
        versionsLabel.alignment = compactStatus ? .center : .left
        detailLabel.isHidden = compactStatus
        header.layer?.backgroundColor = (compactStatus ? TokyoNight.background : TokyoNight.backgroundDeep).cgColor
        footerBackground.isHidden = compactStatus
        divider.isHidden = compactStatus
        notesTitle.isHidden = !hasBody
        notesScrollView.isHidden = !hasBody
        let hadBody = previous.map { !$0.releaseNotes.isEmpty || ($0.phase == .error && $0.message?.isEmpty == false) }
        if hadBody != hasBody {
            notesBottom?.isActive = false
            notesCollapsedHeight?.isActive = false
            notesBottom?.isActive = hasBody
            notesCollapsedHeight?.isActive = !hasBody
        }
        let sameActions = previous.map { old in
            old.actions.count == content.actions.count && zip(old.actions, content.actions).allSatisfy { pair in
                pair.0.title == pair.1.title && pair.0.key == pair.1.key && pair.0.isPrimary == pair.1.isPrimary
            }
        } ?? false
        if !sameActions || wasCompact != compactStatus { rebuildActions(content.actions) }
        let buttonWidth = buttons.reduce(CGFloat(0)) { $0 + $1.fittingSize.width }
            + CGFloat(max(0, footer.arrangedSubviews.count - 1)) * footer.spacing
        let labelWidth = max(titleLabel.intrinsicContentSize.width + (compactStatus ? 0 : 36),
                             versionsLabel.intrinsicContentSize.width)
        let width = hasBody ? 560 : min(560, max(320, ceil(max(labelWidth, buttonWidth)) + 48))
        if contentWidth?.constant != width { progressFill.layer?.removeAnimation(forKey: "preparing") }
        contentWidth?.constant = width
        if let window {
            let size = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: width, height: hasBody ? 500 : compactStatus ? 232 : 250)).size
            if abs(window.frame.width - size.width) > 0.5 || abs(window.frame.height - size.height) > 0.5 {
                let origin = NSPoint(x: window.frame.midX - size.width / 2, y: window.frame.maxY - size.height)
                window.setFrame(NSRect(origin: origin, size: size), display: true, animate: window.isVisible)
            }
        }
        updateProgress(content)
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    func dismiss() {
        clearPendingInput()
        window?.orderOut(nil)
    }

    private func buildContent() {
        guard let root = window?.contentView else { return }
        root.wantsLayer = true
        root.layer?.backgroundColor = TokyoNight.background.cgColor
        header.wantsLayer = true
        header.layer?.backgroundColor = TokyoNight.backgroundDeep.cgColor
        footerBackground.wantsLayer = true
        footerBackground.layer?.backgroundColor = TokyoNight.backgroundDeep.cgColor
        divider.wantsLayer = true
        divider.layer?.backgroundColor = TokyoNight.border.withAlphaComponent(0.6).cgColor

        for view in [header, footerBackground, divider, iconView, titleLabel, detailLabel,
                     versionsLabel, notesTitle, notesScrollView, progressTrack, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        for label in [titleLabel, detailLabel, versionsLabel, notesTitle] {
            label.textColor = TokyoNight.muted
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.lineBreakMode = .byWordWrapping
        }
        titleLabel.font = .systemFont(ofSize: 20, weight: .medium)
        titleLabel.textColor = TokyoNight.foreground
        titleLabel.lineBreakMode = .byTruncatingTail
        detailLabel.font = .systemFont(ofSize: 12.5)
        detailLabel.maximumNumberOfLines = 2
        versionsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        versionsLabel.lineBreakMode = .byTruncatingMiddle
        notesTitle.font = .systemFont(ofSize: 12, weight: .medium)
        iconView.imageScaling = .scaleProportionallyUpOrDown

        notesScrollView.drawsBackground = false
        notesScrollView.hasVerticalScroller = false
        notesScrollView.hasHorizontalScroller = false
        notesScrollView.autohidesScrollers = true
        notesScrollView.borderType = .noBorder
        notesScrollView.documentView = notesView
        notesView.isEditable = false
        notesView.isSelectable = true
        notesView.isRichText = true
        notesView.drawsBackground = false
        notesView.textContainerInset = NSSize(width: 0, height: 2)
        notesView.minSize = .zero
        notesView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        notesView.isVerticallyResizable = true
        notesView.isHorizontallyResizable = false
        notesView.autoresizingMask = [.width]
        notesView.textContainer?.widthTracksTextView = true
        notesView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        notesView.textContainer?.lineFragmentPadding = 0
        notesView.selectedTextAttributes = [.backgroundColor: TokyoNight.selection]

        progressTrack.wantsLayer = true
        progressTrack.layer?.backgroundColor = TokyoNight.border.withAlphaComponent(0.5).cgColor
        progressTrack.layer?.cornerRadius = 1.5
        progressTrack.layer?.masksToBounds = true
        progressFill.wantsLayer = true
        progressFill.layer?.backgroundColor = TokyoNight.blue.cgColor
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(progressFill)
        progressWidth = progressFill.widthAnchor.constraint(equalToConstant: 0)
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10
        notesBottom = notesScrollView.bottomAnchor.constraint(equalTo: footerBackground.topAnchor, constant: -18)
        notesCollapsedHeight = notesScrollView.heightAnchor.constraint(equalToConstant: 0)
        standardStatusConstraints = [
            iconView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            iconView.topAnchor.constraint(equalTo: root.topAnchor, constant: 43),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 41),
            versionsLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 113)
        ]
        compactStatusConstraints = [
            iconView.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: root.topAnchor, constant: 44),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 90),
            versionsLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 122)
        ]
        NSLayoutConstraint.activate(standardStatusConstraints)

        contentWidth = root.widthAnchor.constraint(equalToConstant: 560)
        NSLayoutConstraint.activate([
            contentWidth!,
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 148),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            detailLabel.heightAnchor.constraint(equalToConstant: 34),
            versionsLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            versionsLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            progressTrack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            progressTrack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            progressTrack.topAnchor.constraint(equalTo: root.topAnchor, constant: 139),
            progressTrack.heightAnchor.constraint(equalToConstant: 3),
            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            progressWidth!,
            notesTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            notesTitle.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 19),
            notesScrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            notesScrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            notesScrollView.topAnchor.constraint(equalTo: notesTitle.bottomAnchor, constant: 12),
            footerBackground.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footerBackground.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footerBackground.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footerBackground.heightAnchor.constraint(equalToConstant: 76),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            divider.topAnchor.constraint(equalTo: footerBackground.topAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            footer.centerYAnchor.constraint(equalTo: footerBackground.centerYAnchor),
            footer.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    private func attributedReleaseNotes(_ sections: [AppReleaseNotesSection]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 10
        paragraph.headIndent = 16
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 16)]
        for section in sections {
            if let version = section.version {
                if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
                result.append(NSAttributedString(string: "\(version)\n", attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: TokyoNight.blue
                ]))
            }
            for note in section.notes {
                result.append(NSAttributedString(string: "•\t\(note)\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: TokyoNight.foreground,
                    .paragraphStyle: paragraph
                ]))
            }
        }
        if result.length > 0 {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }
        return result
    }

    private func updateProgress(_ content: UpdateWindowContent) {
        let inProgress = [.checking, .downloading, .extracting, .installing].contains(content.phase)
        progressTrack.isHidden = !inProgress
        guard inProgress else { progressFill.layer?.removeAnimation(forKey: "preparing"); return }
        let trackWidth = (contentWidth?.constant ?? 560) - 48
        if let progress = content.progress {
            progressFill.layer?.removeAnimation(forKey: "preparing")
            progressWidth?.constant = trackWidth * min(1, max(0, progress))
        } else {
            progressWidth?.constant = trackWidth / 3
            if inProgress, progressFill.layer?.animation(forKey: "preparing") == nil {
                let animation = CABasicAnimation(keyPath: "transform.translation.x")
                animation.fromValue = -trackWidth / 3
                animation.toValue = trackWidth
                animation.duration = 1.6
                animation.repeatCount = .infinity
                progressFill.layer?.add(animation, forKey: "preparing")
            }
        }
    }

    private func rebuildActions(_ actions: [UpdateWindowAction]) {
        if buttons.contains(where: { window?.firstResponder === $0 }) {
            window?.makeFirstResponder(nil)
        }
        for view in footer.arrangedSubviews { footer.removeArrangedSubview(view); view.removeFromSuperview() }
        buttons = actions.enumerated().map { index, action in
            let button = UpdateActionButton(action: action)
            button.target = self
            button.action = #selector(pressAction(_:))
            button.tag = index
            return button
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        if compactStatus {
            footer.addArrangedSubview(spacer)
            for button in buttons { footer.addArrangedSubview(button) }
            let trailingSpacer = NSView()
            trailingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            footer.addArrangedSubview(trailingSpacer)
            trailingSpacer.widthAnchor.constraint(equalTo: spacer.widthAnchor).isActive = true
        } else if let secondary = buttons.first, actions.first?.isPrimary == false {
            footer.addArrangedSubview(secondary)
            footer.addArrangedSubview(spacer)
            for button in buttons.dropFirst() { footer.addArrangedSubview(button) }
        } else {
            footer.addArrangedSubview(spacer)
            for button in buttons { footer.addArrangedSubview(button) }
        }
        for (index, button) in buttons.enumerated() {
            button.nextKeyView = buttons[(index + 1) % buttons.count]
        }
    }

    @objc private func pressAction(_ sender: NSButton) {
        clearPendingInput()
        guard let content, content.actions.indices.contains(sender.tag) else { return }
        content.actions[sender.tag].handler()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .option]).isEmpty else {
            clearPendingInput()
            return false
        }
        if event.keyCode == 53 {
            clearPendingInput()
            if !event.isARepeat { requestClose() }
            return true
        }
        if event.keyCode == 48 {
            clearPendingInput()
            guard !buttons.isEmpty else { return true }
            let current = buttons.firstIndex { window?.firstResponder === $0 }
            let direction = event.modifierFlags.contains(.shift) ? -1 : 1
            let index = current.map { ($0 + direction + buttons.count) % buttons.count }
                ?? (direction == 1 ? 0 : buttons.count - 1)
            window?.makeFirstResponder(buttons[index])
            return true
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            clearPendingInput()
            if !event.isARepeat, let button = (window?.firstResponder as? UpdateActionButton)
                ?? buttons.first(where: { $0.isPrimary }) { pressAction(button) }
            return true
        }
        let key = event.charactersIgnoringModifiers ?? ""
        let multiplier = CGFloat(Int(count) ?? 1)
        if event.modifierFlags.contains(.control) {
            clearPendingInput()
            let height = notesScrollView.contentView.bounds.height
            switch key {
            case "d": scrollNotes(by: height / 2 * multiplier)
            case "u": scrollNotes(by: -height / 2 * multiplier)
            case "f": scrollNotes(by: height * multiplier)
            case "b": scrollNotes(by: -height * multiplier)
            default: return false
            }
            return true
        }
        if let digit = key.first, key.count == 1, digit.isASCII, digit.isNumber,
           digit != "0" || !count.isEmpty {
            if count.count < 3 { count.append(digit) }
            pendingG = false
            return true
        }
        switch key {
        case "j": clearPendingInput(); scrollNotes(by: 26 * multiplier); return true
        case "k": clearPendingInput(); scrollNotes(by: -26 * multiplier); return true
        case "g":
            if pendingG { clearPendingInput(); scrollNotes(to: 0) }
            else { pendingG = true }
            return true
        case "G": clearPendingInput(); scrollNotes(to: .greatestFiniteMagnitude); return true
        default: break
        }
        let hadPendingInput = pendingG || !count.isEmpty
        clearPendingInput()
        if let index = content?.actions.firstIndex(where: { $0.key.lowercased() == key.lowercased() }) {
            if !event.isARepeat, !hadPendingInput { pressAction(buttons[index]) }
            return true
        }
        return false
    }

    private func scrollNotes(by offset: CGFloat) {
        scrollNotes(to: notesScrollView.contentView.bounds.minY + offset)
    }

    private func scrollNotes(to offset: CGFloat) {
        notesView.layoutManager?.ensureLayout(for: notesView.textContainer!)
        let clip = notesScrollView.contentView
        let maximum = max(0, notesView.bounds.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: min(maximum, max(0, offset))))
        notesScrollView.reflectScrolledClipView(clip)
    }

    private func clearPendingInput() {
        count = ""
        pendingG = false
    }

    private func requestClose() {
        guard !didNotifyClose else { return }
        didNotifyClose = true
        dismiss()
        onClose?()
    }
}

extension UpdateWindowController: NSWindowDelegate {
    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated { requestClose(); return false }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { requestClose() }
    }
}

private final class UpdatePanelWindow: NSWindow {
    var handleKey: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKey?(event) == true { return }
        super.sendEvent(event)
    }
}

private final class UpdateDragRegion: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

private final class UpdateContentView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

private final class UpdateActionButton: NSButton {
    let shortcut: String
    let isPrimary: Bool
    private var hovering = false

    init(action: UpdateWindowAction) {
        shortcut = action.key.uppercased()
        isPrimary = action.isPrimary
        super.init(frame: .zero)
        title = action.title
        isBordered = false
        font = .systemFont(ofSize: 12.5, weight: .medium)
        translatesAutoresizingMaskIntoConstraints = false
        let textWidth = (title as NSString).size(withAttributes: [.font: font!]).width
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            widthAnchor.constraint(equalToConstant: ceil(textWidth) + 57)
        ])
        setAccessibilityLabel("\(title), \(shortcut)")
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let fill = isPrimary ? TokyoNight.foreground : hovering || isHighlighted ? TokyoNight.panelElevated : TokyoNight.panel
        let text = isPrimary ? TokyoNight.backgroundDeep : TokyoNight.foreground
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        fill.withAlphaComponent(isHighlighted ? 0.85 : 1).setFill()
        path.fill()
        (window?.firstResponder === self ? TokyoNight.blue : TokyoNight.border).setStroke()
        path.lineWidth = 1
        path.stroke()
        (title as NSString).draw(at: NSPoint(x: 12, y: (bounds.height - 16) / 2), withAttributes: [.font: font!, .foregroundColor: text])
        let keyRect = NSRect(x: bounds.width - 33, y: (bounds.height - 20) / 2, width: 21, height: 20)
        text.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: keyRect, xRadius: 5, yRadius: 5).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium), .foregroundColor: text.withAlphaComponent(0.8)]
        let size = (shortcut as NSString).size(withAttributes: attributes)
        (shortcut as NSString).draw(at: NSPoint(x: keyRect.midX - size.width / 2, y: keyRect.midY - size.height / 2), withAttributes: attributes)
    }
}
