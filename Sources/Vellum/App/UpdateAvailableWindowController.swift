@preconcurrency import AppKit

@MainActor
final class UpdateAvailableWindowController: NSWindowController {
    enum Response {
        case install
        case openGitHub
        case later
    }

    private enum ModalCode {
        static let install = NSApplication.ModalResponse(rawValue: 1000)
        static let openGitHub = NSApplication.ModalResponse(rawValue: 1001)
        static let later = NSApplication.ModalResponse(rawValue: 1002)
    }

    private let canInstall: Bool
    private var response: Response = .later

    init(updateVersion: String, currentVersion: String, canInstall: Bool, releaseNotes: [String]) {
        self.canInstall = canInstall

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vellum Update"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(calibratedRed: 0.102, green: 0.106, blue: 0.149, alpha: 1)

        super.init(window: window)
        window.delegate = self
        buildContent(updateVersion: updateVersion, currentVersion: currentVersion, releaseNotes: releaseNotes)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func runModal() -> Response {
        guard let window else { return .later }
        window.center()
        window.makeKeyAndOrderFront(nil)

        let code = NSApp.runModal(for: window)
        window.orderOut(nil)

        switch code {
        case ModalCode.install:
            return .install
        case ModalCode.openGitHub:
            return .openGitHub
        default:
            return response
        }
    }

    private func buildContent(updateVersion: String, currentVersion: String, releaseNotes: [String]) {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(calibratedRed: 0.102, green: 0.106, blue: 0.149, alpha: 1).cgColor

        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = label("Vellum \(updateVersion) is available", size: 17, weight: .semibold)
        titleLabel.alignment = .center

        let detailText = canInstall
            ? "You are currently using Vellum \(currentVersion). Download and install the latest version now."
            : "You are currently using Vellum \(currentVersion). Open GitHub to download the latest version."
        let detailLabel = label(detailText, size: 13, color: mutedColor)
        detailLabel.alignment = .center
        detailLabel.maximumNumberOfLines = 3

        let notesTitle = label("What's new", size: 13, weight: .semibold)
        notesTitle.alignment = .left

        let notesLabel = label(
            releaseNotes.isEmpty
                ? "No release notes were published for this version."
                : releaseNotes.joined(separator: "\n"),
            size: 12.5,
            color: foregroundColor
        )
        notesLabel.maximumNumberOfLines = 7

        let notesPanel = NSView()
        notesPanel.translatesAutoresizingMaskIntoConstraints = false
        notesPanel.wantsLayer = true
        notesPanel.layer?.backgroundColor = NSColor(calibratedRed: 0.142, green: 0.157, blue: 0.232, alpha: 0.82).cgColor
        notesPanel.layer?.cornerRadius = 8
        notesPanel.addSubview(notesLabel)

        let primaryButton = button(canInstall ? "Download and Install" : "Open GitHub", action: #selector(primaryAction))
        primaryButton.bezelColor = NSColor(calibratedRed: 0.122, green: 0.467, blue: 0.902, alpha: 1)

        let githubButton = button(canInstall ? "Open GitHub" : "Later", action: canInstall ? #selector(openGitHubAction) : #selector(laterAction))
        let laterButton = button("Later", action: #selector(laterAction))

        let buttonViews = canInstall ? [primaryButton, githubButton, laterButton] : [primaryButton, githubButton]
        let buttonsStack = NSStackView(views: buttonViews)
        buttonsStack.orientation = .vertical
        buttonsStack.spacing = 8
        buttonsStack.alignment = .width

        let stack = NSStackView(views: [iconView, titleLabel, detailLabel, notesTitle, notesPanel, buttonsStack])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 52),
            iconView.heightAnchor.constraint(equalToConstant: 52),
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detailLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            notesTitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            notesPanel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            notesPanel.heightAnchor.constraint(equalToConstant: 106),
            notesLabel.leadingAnchor.constraint(equalTo: notesPanel.leadingAnchor, constant: 14),
            notesLabel.trailingAnchor.constraint(equalTo: notesPanel.trailingAnchor, constant: -14),
            notesLabel.centerYAnchor.constraint(equalTo: notesPanel.centerYAnchor),
            buttonsStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 48),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor? = nil
    ) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color ?? foregroundColor
        label.backgroundColor = .clear
        label.isBezeled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    @objc private func primaryAction() {
        response = canInstall ? .install : .openGitHub
        NSApp.stopModal(withCode: canInstall ? ModalCode.install : ModalCode.openGitHub)
    }

    @objc private func openGitHubAction() {
        response = .openGitHub
        NSApp.stopModal(withCode: ModalCode.openGitHub)
    }

    @objc private func laterAction() {
        response = .later
        NSApp.stopModal(withCode: ModalCode.later)
    }

    private var foregroundColor: NSColor {
        NSColor(calibratedRed: 0.753, green: 0.792, blue: 0.961, alpha: 1)
    }

    private var mutedColor: NSColor {
        NSColor(calibratedRed: 0.565, green: 0.604, blue: 0.765, alpha: 1)
    }
}

extension UpdateAvailableWindowController: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.stopModal(withCode: ModalCode.later)
        }
    }
}
