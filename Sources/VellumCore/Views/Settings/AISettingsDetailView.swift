import SwiftUI

struct AISettingsDetailView: View {
    @AppStorage(AISettingsKeys.providerID) var providerID = "openai"
    @State var baseURL = ""
    @State var model = ""
    @State var apiKey = ""
    @State var availableModels: [String] = []
    @State var status: AIConnectionStatus = .idle
    @State var isTestingConnection = false
    @State var isTestingFunction = false
    @State var isFetchingModels = false
    @State private var didLoadProviderSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                providerSection
                endpointSection
                modelSection
                validationSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TokyoNight.backgroundColor)
        .onAppear {
            loadProviderSettings(for: providerID, allowsLegacyFallback: true)
        }
        .onChange(of: providerID) { _, newValue in
            loadProviderSettings(for: newValue, allowsLegacyFallback: false)
        }
        .onChange(of: apiKey) { _, _ in
            guard didLoadProviderSettings else { return }
            saveProviderSettings()
            status = .idle
        }
        .onChange(of: baseURL) { _, _ in
            guard didLoadProviderSettings else { return }
            saveProviderSettings()
            availableModels.removeAll()
            status = .idle
        }
        .onChange(of: model) { _, _ in
            guard didLoadProviderSettings else { return }
            saveProviderSettings()
            status = .idle
        }
    }

    var isBusy: Bool {
        isTestingConnection || isTestingFunction || isFetchingModels
    }

    var selectedPreset: AIProviderPreset {
        AIProviderPreset.preset(for: providerID)
    }

    var trimmedModelText: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not set" : trimmed
    }

    var chatEndpointText: String {
        guard let configuration = try? currentConfiguration(requireModel: false) else {
            return "Invalid base URL"
        }

        switch configuration.providerFormat {
        case .openAICompatible:
            return configuration.chatCompletionsURL.absoluteString
        case .anthropicMessages:
            return configuration.messagesURL.absoluteString
        }
    }

    var modelsEndpointText: String {
        guard let configuration = try? currentConfiguration(requireModel: false) else {
            return "Invalid base URL"
        }
        return configuration.modelsURL.absoluteString
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(TokyoNight.cyanColor)
                .frame(width: 36, height: 36)
                .background(TokyoNight.panelElevatedColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TokyoNight.borderColor.opacity(0.75), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text("AI")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Text("Choose a provider, enter its key, then pick the model Vellum should use.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(TokyoNight.mutedColor)
            }

            Spacer()
        }
    }

    private var providerSection: some View {
        SettingsPanel(title: "Provider", systemImage: "building.2") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(AIProviderPreset.presets) { preset in
                    ProviderPresetRow(
                        preset: preset,
                        isSelected: preset.id == providerID
                    ) {
                        providerID = preset.id
                    }
                }
            }
        }
    }

    private var endpointSection: some View {
        SettingsPanel(title: "Endpoint", systemImage: "network") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledSettingsField(title: "Base URL") {
                    StyledTextField(
                        text: $baseURL,
                        placeholder: selectedPreset.baseURL,
                        systemImage: "link"
                    )
                }

                LabeledSettingsField(title: "API Key") {
                    StyledSecureField(
                        text: $apiKey,
                        placeholder: selectedPreset.id == "anthropic" ? "sk-ant-..." : "sk-..."
                    )
                }
            }
        }
    }

    private var modelSection: some View {
        SettingsPanel(title: "Model", systemImage: "cpu") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledSettingsField(title: "Current Model") {
                    StyledTextField(
                        text: $model,
                        placeholder: selectedPreset.defaultModel,
                        systemImage: "cube"
                    )
                }

                HStack(spacing: 10) {
                    Button {
                        fetchModels()
                    } label: {
                        Label(isFetchingModels ? "Fetching" : "Fetch Models", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SettingsActionButtonStyle())
                    .disabled(isBusy)

                    Text(modelsSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(TokyoNight.mutedColor)
                        .lineLimit(1)

                    Spacer()
                }

                if !availableModels.isEmpty {
                    ModelChoiceGrid(models: availableModels, selection: $model)
                }
            }
        }
    }

    private var validationSection: some View {
        SettingsPanel(title: "Validation", systemImage: "checkmark.seal") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Button {
                        testConnection()
                    } label: {
                        Label(isTestingConnection ? "Testing" : "Test Endpoint", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(SettingsActionButtonStyle())
                    .disabled(isBusy)

                    Button {
                        testFunction()
                    } label: {
                        Label(isTestingFunction ? "Testing" : "Test Model", systemImage: "sparkles")
                    }
                    .buttonStyle(SettingsPrimaryButtonStyle())
                    .disabled(isBusy)

                    Spacer()
                }

                AIConnectionStatusRow(status: status, isBusy: isBusy)

                VStack(alignment: .leading, spacing: 8) {
                    diagnosticRow("Request", chatEndpointText)
                    diagnosticRow("Models", modelsEndpointText)
                    diagnosticRow("Selected", trimmedModelText)
                }
                .padding(.top, 2)
            }
        }
    }

    var modelsSummary: String {
        if isFetchingModels {
            return "Loading models from \(selectedPreset.name)..."
        }

        if availableModels.isEmpty {
            return "Fetched models will appear as choices for Current Model."
        }

        return "\(availableModels.count) models loaded."
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TokyoNight.mutedColor)
                .frame(width: 58, alignment: .leading)

            Text(value)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(TokyoNight.foregroundColor)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    func currentConfiguration(requireModel: Bool) throws -> AIConfiguration {
        try AIConfiguration(
            baseURLString: baseURL,
            model: model,
            apiKey: apiKey,
            providerFormat: selectedPreset.format,
            requireModel: requireModel
        )
    }

    private func loadProviderSettings(for id: String, allowsLegacyFallback: Bool) {
        let preset = AIProviderPreset.preset(for: id)
        let defaults = UserDefaults.standard
        didLoadProviderSettings = false
        baseURL = providerSetting(
            key: AISettingsKeys.baseURLKey(for: preset.id),
            legacyKey: AISettingsKeys.baseURL,
            defaultValue: preset.baseURL,
            defaults: defaults,
            allowsLegacyFallback: allowsLegacyFallback
        )
        model = providerSetting(
            key: AISettingsKeys.modelKey(for: preset.id),
            legacyKey: AISettingsKeys.model,
            defaultValue: preset.defaultModel,
            defaults: defaults,
            allowsLegacyFallback: allowsLegacyFallback
        )
        apiKey = providerSetting(
            key: AISettingsKeys.apiKeyKey(for: preset.id),
            legacyKey: AISettingsKeys.apiKey,
            defaultValue: "",
            defaults: defaults,
            allowsLegacyFallback: allowsLegacyFallback
        )
        availableModels.removeAll()
        status = .idle
        didLoadProviderSettings = true
        saveProviderSettings()
    }

    private func providerSetting(
        key: String,
        legacyKey: String,
        defaultValue: String,
        defaults: UserDefaults,
        allowsLegacyFallback: Bool
    ) -> String {
        if defaults.object(forKey: key) != nil {
            return defaults.string(forKey: key) ?? ""
        }

        guard allowsLegacyFallback else {
            return defaultValue
        }

        return defaults.string(forKey: legacyKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? defaultValue
    }

    private func saveProviderSettings() {
        let preset = selectedPreset
        let defaults = UserDefaults.standard
        defaults.set(preset.format.rawValue, forKey: AISettingsKeys.providerFormat)
        defaults.set(baseURL, forKey: AISettingsKeys.baseURLKey(for: preset.id))
        defaults.set(model, forKey: AISettingsKeys.modelKey(for: preset.id))
        defaults.set(apiKey, forKey: AISettingsKeys.apiKeyKey(for: preset.id))
        defaults.set(baseURL, forKey: AISettingsKeys.baseURL)
        defaults.set(model, forKey: AISettingsKeys.model)
        defaults.set(apiKey, forKey: AISettingsKeys.apiKey)
    }
}

private struct SettingsPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(TokyoNight.foregroundColor)

            content
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TokyoNight.panelColor.opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TokyoNight.borderColor.opacity(0.62), lineWidth: 1)
        }
    }
}

private struct LabeledSettingsField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(TokyoNight.mutedColor)

            content
        }
    }
}

private struct StyledTextField: View {
    @Binding var text: String
    let placeholder: String
    let systemImage: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isFocused ? TokyoNight.cyanColor : TokyoNight.mutedColor)
                .frame(width: 16)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(TokyoNight.foregroundColor)
                .textSelection(.enabled)
                .focused($isFocused)
        }
        .settingsInputChrome(isFocused: isFocused)
    }
}

private struct StyledSecureField: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "key.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isFocused ? TokyoNight.cyanColor : TokyoNight.mutedColor)
                .frame(width: 16)

            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(TokyoNight.foregroundColor)
                .focused($isFocused)
        }
        .settingsInputChrome(isFocused: isFocused)
    }
}

private extension View {
    func settingsInputChrome(isFocused: Bool) -> some View {
        self
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(TokyoNight.backgroundDeepColor.opacity(0.92), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isFocused ? TokyoNight.cyanColor.opacity(0.72) : TokyoNight.borderColor.opacity(0.75), lineWidth: 1)
            }
    }
}

private struct ProviderPresetRow: View {
    let preset: AIProviderPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TokyoNight.foregroundColor)

                    Text(preset.summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(TokyoNight.mutedColor)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TokyoNight.cyanColor)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 50)
            .background(isSelected ? TokyoNight.selectionColor.opacity(0.58) : TokyoNight.backgroundDeepColor.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? TokyoNight.cyanColor.opacity(0.58) : TokyoNight.borderColor.opacity(0.52), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ModelChoiceGrid: View {
    let models: [String]
    @Binding var selection: String

    private let columns = [
        GridItem(.adaptive(minimum: 180), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(models, id: \.self) { model in
                Button {
                    selection = model
                } label: {
                    HStack(spacing: 8) {
                        Text(model)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(TokyoNight.foregroundColor)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        if selection == model {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(TokyoNight.cyanColor)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(selection == model ? TokyoNight.selectionColor.opacity(0.5) : TokyoNight.backgroundDeepColor.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(selection == model ? TokyoNight.cyanColor.opacity(0.55) : TokyoNight.borderColor.opacity(0.45), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(TokyoNight.foregroundColor)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                configuration.isPressed
                ? TokyoNight.selectionColor.opacity(0.72)
                : TokyoNight.panelElevatedColor.opacity(0.9),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(TokyoNight.borderColor.opacity(0.72), lineWidth: 1)
            }
    }
}

private struct SettingsPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(TokyoNight.backgroundDeepColor)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                configuration.isPressed
                ? TokyoNight.cyanColor.opacity(0.78)
                : TokyoNight.cyanColor,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }
}
