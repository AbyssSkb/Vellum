import SwiftUI

struct AISettingsDetailView: View {
    @AppStorage(AISettingsKeys.providerID) var providerID = "openai"
    @AppStorage(AISettingsKeys.providerFormat) var providerFormatRaw = AIProviderFormat.openAICompatible.rawValue
    @AppStorage(AISettingsKeys.baseURL) var baseURL = AIConfiguration.defaultBaseURL
    @AppStorage(AISettingsKeys.model) var model = AIConfiguration.defaultModel
    @AppStorage(AISettingsKeys.apiKey) var apiKey = ""
    @State var availableModels: [String] = []
    @State var status: AIConnectionStatus = .idle
    @State var isTestingConnection = false
    @State var isTestingFunction = false
    @State var isFetchingModels = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                providerGrid
                endpointCard
                actionsCard
                diagnosticsCard
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TokyoNight.backgroundColor.opacity(0.95))
        .onChange(of: providerID) { _, newValue in
            applyProviderPreset(id: newValue)
        }
        .onChange(of: apiKey) { _, _ in
            status = .idle
        }
        .onChange(of: baseURL) { _, _ in
            availableModels.removeAll()
            status = .idle
            updateProviderForManualEdits()
        }
        .onChange(of: model) { _, _ in
            status = .idle
            updateProviderForManualEdits()
        }
        .onChange(of: providerFormatRaw) { _, _ in
            status = .idle
            updateProviderForManualEdits()
        }
    }

    var isBusy: Bool {
        isTestingConnection || isTestingFunction || isFetchingModels
    }

    var providerFormat: AIProviderFormat {
        AIProviderFormat(rawValue: providerFormatRaw) ?? .openAICompatible
    }

    var selectedPreset: AIProviderPreset {
        AIProviderPreset.presets.first { $0.id == providerID }
            ?? AIProviderPreset.presets.first { $0.id == AIProviderPreset.customID }!
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
        VStack(alignment: .leading, spacing: 6) {
            Text("AI Provider")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(TokyoNight.foregroundColor)

            Text("Configure the model Vellum uses for selection explanations.")
                .font(.system(size: 13))
                .foregroundStyle(TokyoNight.mutedColor)
        }
    }

    private var providerGrid: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Provider", systemImage: "building.2")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                    ForEach(AIProviderPreset.presets) { preset in
                        ProviderPresetButton(
                            preset: preset,
                            isSelected: preset.id == providerID
                        ) {
                            providerID = preset.id
                        }
                    }
                }
            }
        }
    }

    private var endpointCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle("Endpoint", systemImage: "network")

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                    settingsRow(title: "Format") {
                        Picker("Format", selection: $providerFormatRaw) {
                            ForEach(AIProviderFormat.allCases) { format in
                                Text(format.title).tag(format.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    settingsRow(title: "Base URL") {
                        TextField(AIConfiguration.defaultBaseURL, text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.URL)
                    }

                    settingsRow(title: "API Key") {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    settingsRow(title: "Model") {
                        TextField(AIConfiguration.defaultModel, text: $model)
                            .textFieldStyle(.roundedBorder)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var actionsCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle("Validation", systemImage: "checkmark.seal")

                HStack(spacing: 10) {
                    Button {
                        fetchModels()
                    } label: {
                        Label(isFetchingModels ? "Fetching" : "Fetch Models", systemImage: "arrow.clockwise")
                    }
                    .disabled(isBusy)

                    Button {
                        testConnection()
                    } label: {
                        Label(isTestingConnection ? "Testing" : "Test Endpoint", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .disabled(isBusy)

                    Button {
                        testFunction()
                    } label: {
                        Label(isTestingFunction ? "Testing" : "Test Model", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
                }

                if !availableModels.isEmpty {
                    Picker("Fetched Models", selection: $model) {
                        ForEach(availableModels, id: \.self) { fetchedModel in
                            Text(fetchedModel).tag(fetchedModel)
                        }
                    }
                }

                AIConnectionStatusRow(status: status, isBusy: isBusy)
            }
        }
    }

    private var diagnosticsCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Resolved Endpoints", systemImage: "terminal")

                diagnosticRow("Request Endpoint", chatEndpointText)
                diagnosticRow("Models Endpoint", modelsEndpointText)
                diagnosticRow("Current Model", trimmedModelText)
            }
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TokyoNight.panelElevatedColor.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TokyoNight.borderColor.opacity(0.55), lineWidth: 1)
            }
    }

    private func cardTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(TokyoNight.foregroundColor)
    }

    private func settingsRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TokyoNight.mutedColor)
                .frame(width: 82, alignment: .leading)

            content()
        }
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TokyoNight.mutedColor)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(TokyoNight.foregroundColor.opacity(0.82))
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    func currentConfiguration(requireModel: Bool) throws -> AIConfiguration {
        try AIConfiguration(
            baseURLString: baseURL,
            model: model,
            apiKey: apiKey,
            providerFormat: providerFormat,
            requireModel: requireModel
        )
    }

    private func applyProviderPreset(id: String) {
        guard let preset = AIProviderPreset.presets.first(where: { $0.id == id }) else { return }

        baseURL = preset.baseURL
        model = preset.defaultModel
        providerFormatRaw = preset.format.rawValue
        availableModels.removeAll()
        status = .idle
    }

    private func updateProviderForManualEdits() {
        guard let selected = AIProviderPreset.presets.first(where: { $0.id == providerID }),
              providerID != AIProviderPreset.customID else {
            return
        }

        if baseURL != selected.baseURL || model != selected.defaultModel || providerFormat != selected.format {
            providerID = AIProviderPreset.customID
        }
    }
}

private struct ProviderPresetButton: View {
    let preset: AIProviderPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(preset.name)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(TokyoNight.cyanColor)
                    }
                }

                Text(preset.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(TokyoNight.mutedColor)
                    .lineLimit(2)

                Text(preset.defaultModel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(TokyoNight.foregroundColor.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(isSelected ? TokyoNight.selectionColor.opacity(0.45) : TokyoNight.panelColor.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? TokyoNight.cyanColor.opacity(0.6) : TokyoNight.borderColor.opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
