@preconcurrency import AppKit
import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case ai
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ai:
            return "AI"
        case .shortcuts:
            return "Shortcuts"
        }
    }

    var subtitle: String {
        switch self {
        case .ai:
            return "Provider and model"
        case .shortcuts:
            return "Keyboard map"
        }
    }

    var systemImage: String {
        switch self {
        case .ai:
            return "sparkles"
        case .shortcuts:
            return "keyboard"
        }
    }
}

enum AIConnectionStatus: Equatable {
    case idle
    case working(String)
    case success(String)
    case failure(String)

    var text: String {
        switch self {
        case .idle:
            return "Not checked"
        case .working(let message), .success(let message), .failure(let message):
            return message
        }
    }

    var color: NSColor {
        switch self {
        case .idle:
            return TokyoNight.muted
        case .working:
            return TokyoNight.blue
        case .success:
            return NSColor(calibratedRed: 0.62, green: 0.86, blue: 0.49, alpha: 1)
        case .failure:
            return TokyoNight.red
        }
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}

struct AISettingsView: View {
    @State private var selectedCategory: SettingsCategory = .ai

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selectedCategory: $selectedCategory)
                .frame(width: 190)

            TokyoNightDivider(axis: .vertical)

            Group {
                switch selectedCategory {
                case .ai:
                    AISettingsDetailView()
                case .shortcuts:
                    ShortcutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 840, height: 560)
        .background(TokyoNight.backgroundColor)
        .preferredColorScheme(.dark)
    }
}

struct SettingsSidebar: View {
    @Binding var selectedCategory: SettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("VimPDF")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Text("Settings")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TokyoNight.mutedColor)
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 8)

            ForEach(SettingsCategory.allCases) { category in
                Button {
                    selectedCategory = category
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: category.systemImage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(selectedCategory == category ? TokyoNight.blueColor : TokyoNight.mutedColor)
                            .frame(width: 20)

                        Text(category.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TokyoNight.foregroundColor)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(selectedCategory == category ? TokyoNight.selectionColor.opacity(0.92) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(selectedCategory == category ? TokyoNight.blueColor.opacity(0.22) : Color.clear, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
            }

            Spacer()
        }
        .background {
            ZStack {
                SidebarVisualEffectBackground()
                TokyoNight.backgroundDeepColor.opacity(0.68)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(TokyoNight.borderColor.opacity(0.42))
                .frame(width: 1)
        }
    }
}

struct AISettingsDetailView: View {
    @AppStorage(AISettingsKeys.baseURL) private var baseURL = AIConfiguration.defaultBaseURL
    @AppStorage(AISettingsKeys.model) private var model = AIConfiguration.defaultModel
    @AppStorage(AISettingsKeys.apiKey) private var apiKey = ""
    @State private var availableModels: [String] = []
    @State private var status: AIConnectionStatus = .idle
    @State private var isTestingConnection = false
    @State private var isFetchingModels = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SettingsGroup(title: "Provider") {
                        SettingsRow(title: "Base URL", systemImage: "link") {
                            SettingsInputContainer {
                                TextField(AIConfiguration.defaultBaseURL, text: $baseURL)
                                    .textFieldStyle(.plain)
                            }
                            .frame(width: 360)
                        }

                        SettingsRow(title: "API Key", systemImage: "key") {
                            SettingsInputContainer {
                                SecureField("sk-...", text: $apiKey)
                                    .textFieldStyle(.plain)
                            }
                            .frame(width: 360)
                        }
                    }

                    SettingsGroup(title: "Model") {
                        SettingsRow(title: "Model", systemImage: "cube.transparent") {
                            ModelPickerField(
                                text: $model,
                                models: availableModels,
                                placeholder: AIConfiguration.defaultModel
                            )
                            .frame(width: 360)
                        }

                        SettingsRow(title: "Connection", systemImage: "circle.hexagongrid") {
                            AIConnectionLight(status: status, isBusy: isBusy)

                            Spacer(minLength: 12)

                            Button {
                                fetchModels()
                            } label: {
                                Label(isFetchingModels ? "Fetching" : "Fetch", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(SettingsActionButtonStyle())
                            .disabled(isBusy)

                            Button {
                                testConnection()
                            } label: {
                                Label(isTestingConnection ? "Testing" : "Test", systemImage: "checkmark.circle")
                            }
                            .buttonStyle(SettingsActionButtonStyle(accentColor: TokyoNight.blue))
                            .disabled(isBusy)
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
            }
        }
        .background(TokyoNight.backgroundColor)
        .onChange(of: apiKey) { _, _ in
            status = .idle
        }
        .onChange(of: baseURL) { _, _ in
            availableModels.removeAll()
            status = .idle
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Text("OpenAI-compatible provider and model")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TokyoNight.mutedColor)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(TokyoNight.backgroundColor)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TokyoNight.borderColor.opacity(0.26))
                .frame(height: 1)
        }
    }

    private var isBusy: Bool {
        isTestingConnection || isFetchingModels
    }

    private func testConnection() {
        isTestingConnection = true
        status = .working("Testing model...")

        Task { @MainActor in
            defer { isTestingConnection = false }

            do {
                let configuration = try currentConfiguration(requireModel: true)
                _ = try await AIExplanationClient.testConnection(configuration: configuration)
                status = .success("Model ready")
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }

    private func fetchModels() {
        isFetchingModels = true
        status = .working("Fetching models...")

        Task { @MainActor in
            defer { isFetchingModels = false }

            do {
                let configuration = try currentConfiguration(requireModel: false)
                let models = try await AIExplanationClient.fetchModels(configuration: configuration)
                availableModels = models

                let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
                if let firstModel = models.first,
                   trimmedModel.isEmpty || !models.contains(model) {
                    model = firstModel
                }

                status = models.isEmpty
                    ? .success("Connected. No models returned.")
                    : .success("\(models.count) models loaded.")
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }

    private func currentConfiguration(requireModel: Bool) throws -> AIConfiguration {
        return try AIConfiguration.current(requireModel: requireModel)
    }
}

struct SettingsField<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TokyoNight.mutedColor)

            content
        }
    }
}

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

struct ShortcutSettingsView: View {
    private let groups = ShortcutCatalog.groups

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shortcuts")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(TokyoNight.foregroundColor)

                    Text("Vim-style keyboard map")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TokyoNight.mutedColor)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(TokyoNight.panelColor.opacity(0.78))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(TokyoNight.borderColor.opacity(0.32))
                    .frame(height: 1)
            }

            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 250), spacing: 14),
                        GridItem(.flexible(minimum: 250), spacing: 14)
                    ],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(groups) { group in
                        ShortcutGroupCard(group: group)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
            }
        }
        .background(TokyoNight.backgroundColor)
    }
}

struct ShortcutGroup: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let items: [ShortcutItem]
}

struct ShortcutItem: Identifiable {
    let id = UUID()
    let keys: [String]
    let action: String
}

enum ShortcutCatalog {
    static let groups: [ShortcutGroup] = [
        ShortcutGroup(
            title: "Files and Tabs",
            systemImage: "doc.on.doc",
            items: [
                ShortcutItem(keys: ["o"], action: "Open PDF in current tab"),
                ShortcutItem(keys: ["O"], action: "Open PDF in new tab"),
                ShortcutItem(keys: ["x"], action: "Close current tab"),
                ShortcutItem(keys: ["X"], action: "Restore closed PDF"),
                ShortcutItem(keys: ["[", "]", "H", "L"], action: "Switch tabs")
            ]
        ),
        ShortcutGroup(
            title: "Reading",
            systemImage: "arrow.up.and.down",
            items: [
                ShortcutItem(keys: ["j", "k"], action: "Smooth scroll"),
                ShortcutItem(keys: ["u", "d"], action: "Large smooth scroll"),
                ShortcutItem(keys: ["h", "l"], action: "Horizontal scroll"),
                ShortcutItem(keys: ["f", "b"], action: "Move exactly one page"),
                ShortcutItem(keys: ["gg", "G", "[num]G"], action: "Jump to first, last, or numbered page"),
                ShortcutItem(keys: ["Ctrl O", "Ctrl I"], action: "Jump backward or forward")
            ]
        ),
        ShortcutGroup(
            title: "View",
            systemImage: "rectangle.expand.vertical",
            items: [
                ShortcutItem(keys: ["=", "-"], action: "Smooth zoom"),
                ShortcutItem(keys: ["z"], action: "Fit width"),
                ShortcutItem(keys: ["0"], action: "Fit page"),
                ShortcutItem(keys: ["Tab", "t"], action: "Toggle contents")
            ]
        ),
        ShortcutGroup(
            title: "Highlights and AI",
            systemImage: "highlighter",
            items: [
                ShortcutItem(keys: ["m"], action: "Highlight selection"),
                ShortcutItem(keys: ["c"], action: "Cycle highlight color"),
                ShortcutItem(keys: ["d"], action: "Delete selected highlight"),
                ShortcutItem(keys: ["a"], action: "Explain selected text")
            ]
        ),
        ShortcutGroup(
            title: "Text Selection",
            systemImage: "selection.pin.in.out",
            items: [
                ShortcutItem(keys: ["h", "j", "k", "l"], action: "Move selection endpoint"),
                ShortcutItem(keys: ["w", "b", "e"], action: "Move by word"),
                ShortcutItem(keys: ["Esc"], action: "Clear text selection")
            ]
        ),
        ShortcutGroup(
            title: "Contents",
            systemImage: "list.bullet.indent",
            items: [
                ShortcutItem(keys: ["j", "k"], action: "Move outline selection"),
                ShortcutItem(keys: ["h", "l"], action: "Collapse or expand"),
                ShortcutItem(keys: ["Enter"], action: "Jump to selected item")
            ]
        )
    ]
}

struct ShortcutRow: View {
    let item: ShortcutItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.action)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(TokyoNight.foregroundColor.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                ForEach(item.keys, id: \.self) { key in
                    ShortcutKeyCap(text: key)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

struct ShortcutGroupCard: View {
    let group: ShortcutGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: group.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TokyoNight.blueColor)
                    .frame(width: 18)

                Text(group.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Spacer(minLength: 0)
            }
            .padding(.bottom, 2)

            VStack(spacing: 0) {
                ForEach(group.items) { item in
                    ShortcutRow(item: item)

                    if item.id != group.items.last?.id {
                        Rectangle()
                            .fill(TokyoNight.borderColor.opacity(0.2))
                            .frame(height: 1)
                    }
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(TokyoNight.panelColor.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TokyoNight.borderColor.opacity(0.34), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ShortcutKeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(TokyoNight.foregroundColor)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(TokyoNight.backgroundDeepColor.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(TokyoNight.borderColor.opacity(0.55), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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

struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(TokyoNight.blueColor)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TokyoNight.foregroundColor)
            }

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TokyoNight.panelElevatedColor.opacity(0.62))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(TokyoNight.borderColor.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct AIStatusView: View {
    let status: AIConnectionStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(nsColor: status.color))
                .frame(width: 7, height: 7)
            Text(status.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TokyoNight.foregroundColor.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(TokyoNight.backgroundDeepColor.opacity(0.8))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color(nsColor: status.color).opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
