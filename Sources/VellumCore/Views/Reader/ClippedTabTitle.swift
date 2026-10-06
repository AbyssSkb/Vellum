@preconcurrency import AppKit
import SwiftUI

struct ClippedTabTitle: NSViewRepresentable {
    let title: String
    let isSelected: Bool
    var isHovered = false

    func makeNSView(context: Context) -> PDFOutlineTitleView {
        let view = PDFOutlineTitleView()
        let textField = view.textField
        textField.alignment = .left
        textField.isSelectable = false
        textField.allowsDefaultTighteningForTruncation = false
        textField.backgroundColor = .clear
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ view: PDFOutlineTitleView, context: Context) {
        let textField = view.textField
        textField.font = .systemFont(ofSize: 12.5, weight: isSelected ? .medium : .regular)
        textField.textColor = isSelected || isHovered
            ? TokyoNight.foreground
            : TokyoNight.muted
        view.invalidateIntrinsicContentSize()
        // Preserve the shared marquee's progress across unrelated reader updates.
        if view.title != title { view.title = title }
        let shouldScroll = isSelected || isHovered
        if view.isSelected != shouldScroll { view.isSelected = shouldScroll }
        view.needsLayout = true
    }
}
