@preconcurrency import AppKit
import SwiftUI

struct ClippedTabTitle: NSViewRepresentable {
    let title: String
    let isSelected: Bool

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(labelWithString: title)
        textField.lineBreakMode = .byClipping
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
        textField.font = .systemFont(ofSize: 12.5, weight: isSelected ? .semibold : .regular)
        textField.textColor = isSelected
            ? TokyoNight.foreground
            : TokyoNight.foreground.withAlphaComponent(0.76)
        textField.lineBreakMode = .byClipping
        textField.maximumNumberOfLines = 1
        textField.alignment = .left
    }
}
