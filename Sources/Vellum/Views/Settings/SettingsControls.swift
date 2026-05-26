@preconcurrency import AppKit
import SwiftUI

struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TokyoNight.mutedColor)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content
            }
            .background(TokyoNight.panelColor.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TokyoNight.borderColor.opacity(0.34), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TokyoNight.mutedColor)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TokyoNight.foregroundColor.opacity(0.9))
            }
            .frame(width: 150, alignment: .leading)

            Spacer(minLength: 12)

            content
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TokyoNight.borderColor.opacity(0.22))
                .frame(height: 1)
                .padding(.leading, 48)
        }
    }
}

struct SettingsInputContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 9) {
            content
        }
        .font(.system(size: 13))
        .foregroundStyle(TokyoNight.foregroundColor)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(TokyoNight.backgroundDeepColor.opacity(0.58))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TokyoNight.borderColor.opacity(0.38), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ModelPickerField: View {
    @Binding var text: String
    let models: [String]
    let placeholder: String

    var body: some View {
        SettingsInputContainer {
            ModelComboBox(text: $text, models: models, placeholder: placeholder)
                .frame(height: 24)
        }
    }
}

struct SettingsActionButtonStyle: ButtonStyle {
    var accentColor: NSColor = TokyoNight.panelElevated

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(TokyoNight.foregroundColor)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Color(nsColor: accentColor).opacity(configuration.isPressed ? 0.92 : 0.68))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(TokyoNight.borderColor.opacity(0.48), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct AIConnectionLight: View {
    let status: AIConnectionStatus
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(Color(nsColor: status.color))
                    .frame(width: 9, height: 9)
                    .overlay(
                        Circle()
                            .stroke(TokyoNight.foregroundColor.opacity(0.16), lineWidth: 1)
                    )
            }

            Text(status.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(status.isIdle ? TokyoNight.mutedColor : TokyoNight.foregroundColor.opacity(0.86))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


struct ModelComboBox: NSViewRepresentable {
    @Binding var text: String
    let models: [String]
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.delegate = context.coordinator
        comboBox.target = context.coordinator
        comboBox.action = #selector(Coordinator.commitSelection(_:))
        comboBox.completes = true
        comboBox.usesDataSource = false
        comboBox.isEditable = true
        comboBox.isBordered = false
        comboBox.drawsBackground = false
        comboBox.hasVerticalScroller = true
        comboBox.numberOfVisibleItems = 12
        comboBox.font = .systemFont(ofSize: 13)
        comboBox.controlSize = .regular
        comboBox.textColor = TokyoNight.foreground
        comboBox.backgroundColor = .clear
        comboBox.placeholderString = placeholder
        comboBox.addItems(withObjectValues: models)
        comboBox.stringValue = text
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        context.coordinator.parent = self

        let currentItems = (0..<comboBox.numberOfItems).compactMap {
            comboBox.itemObjectValue(at: $0) as? String
        }
        if currentItems != models {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: models)
        }

        comboBox.placeholderString = placeholder
        comboBox.font = .systemFont(ofSize: 13)
        comboBox.textColor = TokyoNight.foreground
        comboBox.backgroundColor = .clear
        comboBox.drawsBackground = false
        comboBox.isBordered = false
        if comboBox.stringValue != text, comboBox.currentEditor() == nil {
            comboBox.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: ModelComboBox

        init(_ parent: ModelComboBox) {
            self.parent = parent
        }

        @objc func commitSelection(_ sender: NSComboBox) {
            parent.text = sender.stringValue
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            parent.text = comboBox.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            parent.text = comboBox.stringValue
        }
    }
}
