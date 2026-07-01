@preconcurrency import AppKit
import VellumCore

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
    private let language = AppUILanguage.saved()
    private var response: Response = .later

    init(updateVersion: String, currentVersion: String, canInstall: Bool, releaseNotes: [String]) {
        self.canInstall = canInstall

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 448),
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
        contentView.layer?.backgroundColor = TokyoNight.backgroundDeep.cgColor

        let iconWell = NSView()
        iconWell.translatesAutoresizingMaskIntoConstraints = false
        iconWell.wantsLayer = true
        iconWell.layer?.backgroundColor = TokyoNight.panelElevated.cgColor
        iconWell.layer?.cornerRadius = 10
        iconWell.layer?.borderWidth = 1
        iconWell.layer?.borderColor = TokyoNight.border.cgColor

        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconWell.addSubview(iconView)

        let titleLabel = label(language.text(.updateAvailableTitle(updateVersion)), size: 17, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        let detailText = canInstall
            ? language.text(.updateAvailableInstallDetail(current: currentVersion))
            : language.text(.updateAvailableGitHubDetail(current: currentVersion))
        let detailLabel = label(detailText, size: 13, color: mutedColor)
        detailLabel.maximumNumberOfLines = 2

        let titleStack = NSStackView(views: [titleLabel, detailLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 5

        let headerStack = NSStackView(views: [iconWell, titleStack])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 13
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let notesTitle = label(language.text(.whatsNew), size: 12.5, weight: .semibold)
        notesTitle.translatesAutoresizingMaskIntoConstraints = false

        let noteRows = releaseNotes.isEmpty
            ? [fallbackNoteRow()]
            : releaseNotes.map(noteRow)
        let notesPanel = NSView()
        notesPanel.translatesAutoresizingMaskIntoConstraints = false
        notesPanel.wantsLayer = true
        notesPanel.layer?.backgroundColor = TokyoNight.panel.cgColor.copy(alpha: 0.82)
        notesPanel.layer?.cornerRadius = 8
        notesPanel.layer?.borderWidth = 1
        notesPanel.layer?.borderColor = TokyoNight.border.withAlphaComponent(0.62).cgColor

        let notesStack = NSStackView(views: noteRows)
        notesStack.orientation = .vertical
        notesStack.alignment = .width
        notesStack.spacing = 9
        notesStack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = FlippedDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(notesStack)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = documentView
        notesPanel.addSubview(scrollView)

        let primaryButton = button(
            canInstall ? language.text(.downloadAndInstall) : language.text(.openGitHub),
            action: #selector(primaryAction),
            isPrimary: true
        )
        let openGitHubButton = button(language.text(.openGitHub), action: #selector(openGitHubAction))
        let laterButton = button(language.text(.later), action: #selector(laterAction))

        let actionSpacer = NSView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttonViews = canInstall
            ? [laterButton, actionSpacer, openGitHubButton, primaryButton]
            : [laterButton, actionSpacer, primaryButton]
        let actionStack = NSStackView(views: buttonViews)
        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.distribution = .fill
        actionStack.spacing = 9
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(headerStack)
        contentView.addSubview(notesTitle)
        contentView.addSubview(notesPanel)
        contentView.addSubview(actionStack)

        let sidePadding: CGFloat = 26

        NSLayoutConstraint.activate([
            iconWell.widthAnchor.constraint(equalToConstant: 48),
            iconWell.heightAnchor.constraint(equalToConstant: 48),
            iconView.centerXAnchor.constraint(equalTo: iconWell.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 33),
            iconView.heightAnchor.constraint(equalToConstant: 33),

            headerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: sidePadding),
            headerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -sidePadding),
            headerStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 43),

            titleLabel.widthAnchor.constraint(equalTo: titleStack.widthAnchor),
            detailLabel.widthAnchor.constraint(equalTo: titleStack.widthAnchor),

            notesTitle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: sidePadding),
            notesTitle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -sidePadding),
            notesTitle.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 22),

            notesPanel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: sidePadding),
            notesPanel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -sidePadding),
            notesPanel.topAnchor.constraint(equalTo: notesTitle.bottomAnchor, constant: 9),
            notesPanel.bottomAnchor.constraint(equalTo: actionStack.topAnchor, constant: -20),

            scrollView.leadingAnchor.constraint(equalTo: notesPanel.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: notesPanel.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: notesPanel.topAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: notesPanel.bottomAnchor, constant: -12),

            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            notesStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            notesStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            notesStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            notesStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),

            actionStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: sidePadding),
            actionStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -sidePadding),
            actionStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22),
            actionStack.heightAnchor.constraint(equalToConstant: 34),

            laterButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 86),
            primaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: canInstall ? 150 : 118),
            openGitHubButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 110)
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

    private func noteRow(_ text: String) -> NSView {
        let bullet = NSTextField(labelWithString: "•")
        bullet.font = .systemFont(ofSize: 14, weight: .semibold)
        bullet.textColor = TokyoNight.cyan
        bullet.alignment = .center
        bullet.translatesAutoresizingMaskIntoConstraints = false

        let textLabel = label(cleanDisplayNote(text), size: 12.5, color: foregroundColor)
        textLabel.maximumNumberOfLines = 0

        let row = NSStackView(views: [bullet, textLabel])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 9
        row.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            bullet.widthAnchor.constraint(equalToConstant: 12)
        ])
        return row
    }

    private func fallbackNoteRow() -> NSView {
        let noteLabel = label(language.text(.releaseNotesFallback), size: 12.5, color: mutedColor)
        noteLabel.maximumNumberOfLines = 0
        return noteLabel
    }

    private func cleanDisplayNote(_ note: String) -> String {
        var text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix("-") || text.hasPrefix("*") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
    }

    private func button(_ title: String, action: Selector, isPrimary: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.contentTintColor = isPrimary ? TokyoNight.backgroundDeep : TokyoNight.foreground
        button.wantsLayer = true
        button.layer?.backgroundColor = (isPrimary ? TokyoNight.cyan : TokyoNight.panelElevated).cgColor
        button.layer?.cornerRadius = 7
        button.layer?.borderWidth = 1
        button.layer?.borderColor = (isPrimary ? TokyoNight.cyan : TokyoNight.border).withAlphaComponent(0.75).cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
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
        TokyoNight.foreground
    }

    private var mutedColor: NSColor {
        TokyoNight.muted
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

extension UpdateAvailableWindowController: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.stopModal(withCode: ModalCode.later)
        }
    }
}
