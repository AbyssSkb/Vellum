@preconcurrency import AppKit
import SwiftUI

struct ClippedTabTitle: NSViewRepresentable {
    let title: String
    let isSelected: Bool
    var isHovered = false

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(labelWithString: title)
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.alignment = .left
        textField.isSelectable = false
        textField.allowsDefaultTighteningForTruncation = false
        textField.backgroundColor = .clear
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        textField.stringValue = title
        textField.font = .systemFont(ofSize: 12.5, weight: isSelected ? .medium : .regular)
        textField.textColor = isSelected || isHovered
            ? TokyoNight.foreground
            : TokyoNight.muted
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.alignment = .left
    }
}
