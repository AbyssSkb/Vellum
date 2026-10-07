@preconcurrency import AppKit
import SwiftUI

struct ClippedTabTitle: NSViewRepresentable {
    let title: String
    let isSelected: Bool
    var isHovered = false

    @MainActor
    final class Coordinator {
        var title: String?
        var isSelected = false
        var isHovered = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFOutlineTitleView {
        let view = PDFOutlineTitleView()
        view.repeatsMarquee = false
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
        let previous = context.coordinator
        let activated = isSelected && (!previous.isSelected || previous.title != title)
        let hoverEntered = isHovered && !previous.isHovered
        let hoverLeft = !isHovered && previous.isHovered
        let deselected = !isSelected && previous.isSelected && !isHovered
        previous.title = title
        previous.isSelected = isSelected
        previous.isHovered = isHovered

        if view.title != title { view.title = title }
        if hoverLeft || deselected { view.stopMarquee() }
        if activated || hoverEntered { view.playMarqueeOnce() }
        view.needsLayout = true
    }
}
