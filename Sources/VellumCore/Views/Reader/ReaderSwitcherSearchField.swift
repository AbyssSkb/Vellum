@preconcurrency import AppKit
import SwiftUI

struct ReaderSwitcherSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ReaderSwitcherTextField {
        let textField = ReaderSwitcherTextField()
        textField.delegate = context.coordinator
        textField.onMoveUp = onMoveUp
        textField.onMoveDown = onMoveDown
        textField.onCommit = onCommit
        textField.onCancel = onCancel
        textField.configure(placeholder: placeholder)
        focus(textField)
        return textField
    }

    func updateNSView(_ textField: ReaderSwitcherTextField, context: Context) {
        textField.onMoveUp = onMoveUp
        textField.onMoveDown = onMoveDown
        textField.onCommit = onCommit
        textField.onCancel = onCancel
        textField.configurePlaceholder(placeholder)

        if textField.stringValue != text {
            textField.stringValue = text
        }

        context.coordinator.text = $text
        focus(textField)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    private func focus(_ textField: ReaderSwitcherTextField) {
        DispatchQueue.main.async {
            guard textField.window?.firstResponder !== textField.currentEditor() else { return }
            textField.window?.makeFirstResponder(textField)
            textField.currentEditor()?.selectedRange = NSRange(location: textField.stringValue.count, length: 0)
        }
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
            guard let textField = control as? ReaderSwitcherTextField else { return false }
            return textField.performCommand(commandSelector)
        }
    }
}

struct ReaderSwitcherVisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        view.isEmphasized = false
    }
}

final class ReaderSwitcherTextField: NSTextField {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    func configure(placeholder: String) {
        cell = ReaderSwitcherTextFieldCell(textCell: "")
        font = .systemFont(ofSize: 22, weight: .medium)
        textColor = TokyoNight.foreground
        configurePlaceholder(placeholder)
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

    func configurePlaceholder(_ placeholder: String) {
        placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: TokyoNight.muted.withAlphaComponent(0.92),
                .font: NSFont.systemFont(ofSize: 22, weight: .regular)
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

private final class ReaderSwitcherTextFieldCell: NSTextFieldCell {
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
