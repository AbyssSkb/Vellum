@preconcurrency import AppKit
import SwiftUI

struct ListSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let font: NSFont
    let canFocus: () -> Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ListSearchTextField {
        let textField = ListSearchTextField()
        textField.delegate = context.coordinator
        textField.onMoveUp = onMoveUp
        textField.onMoveDown = onMoveDown
        textField.onCommit = onCommit
        textField.onCancel = onCancel
        textField.configure(placeholder: placeholder, font: font)
        textField.canFocus = canFocus
        return textField
    }

    func updateNSView(_ nsView: ListSearchTextField, context: Context) {
        nsView.onMoveUp = onMoveUp
        nsView.onMoveDown = onMoveDown
        nsView.onCommit = onCommit
        nsView.onCancel = onCancel
        nsView.canFocus = canFocus
        nsView.configurePlaceholder(placeholder, font: font)

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        context.coordinator.text = $text
        nsView.focusInitiallyIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard !textView.hasMarkedText(), let textField = control as? ListSearchTextField else { return false }
            return textField.performCommand(commandSelector)
        }
    }
}

final class ListSearchTextField: NSTextField {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var canFocus: (() -> Bool)?
    private var needsInitialFocus = true

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusInitiallyIfNeeded()
    }

    func focusInitiallyIfNeeded() {
        guard needsInitialFocus, let window else { return }
        if let responder = window.firstResponder,
           responder === self || responder === currentEditor() {
            needsInitialFocus = false
            return
        }
        let expectedResponder = window.firstResponder
        DispatchQueue.main.async { [weak self, weak window, weak expectedResponder] in
            guard let self, let window, self.needsInitialFocus,
                  self.window === window, self.superview != nil,
                  self.canFocus?() == true,
                  NSApp.modalWindow == nil, window.attachedSheet == nil,
                  NSApp.keyWindow == nil || window.isKeyWindow else { return }
            self.needsInitialFocus = false
            guard window.firstResponder === expectedResponder else { return }
            window.makeFirstResponder(self)
            self.currentEditor()?.selectedRange = NSRange(location: self.stringValue.utf16.count, length: 0)
        }
    }

    func configure(placeholder: String, font: NSFont) {
        cell = ListSearchTextFieldCell(textCell: "")
        self.font = font
        textColor = VellumColors.foreground
        configurePlaceholder(placeholder, font: font)
        backgroundColor = .clear
        isBordered = false
        isBezeled = false
        drawsBackground = false
        isEditable = true
        isSelectable = true
        isEnabled = true
        focusRingType = .none
        cell?.usesSingleLineMode = true
        cell?.wraps = false
        cell?.isScrollable = true
    }

    func configurePlaceholder(_ placeholder: String, font: NSFont) {
        placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: VellumColors.muted.withAlphaComponent(0.92),
                .font: NSFont.systemFont(ofSize: font.pointSize, weight: .regular)
            ]
        )
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1b}" {
            onCancel?()
            return
        }

        switch event.specialKey {
        case .upArrow:
            onMoveUp?()
        case .downArrow:
            onMoveDown?()
        case .carriageReturn, .newline:
            onCommit?()
        default:
            super.keyDown(with: event)
        }
    }

    func performCommand(_ commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            onMoveUp?()
            return true
        case #selector(NSResponder.moveDown(_:)):
            onMoveDown?()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            onCommit?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
            return true
        default:
            return false
        }
    }
}

private final class ListSearchTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        let textHeight = cellSize(forBounds: rect).height
        drawingRect.origin.y += max(0, (rect.height - textHeight) / 2)
        drawingRect.size.height = min(drawingRect.height, textHeight)
        return drawingRect
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(
            withFrame: drawingRect(forBounds: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }
}
