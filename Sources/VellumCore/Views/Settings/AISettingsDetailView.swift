import SwiftUI

struct AISettingsDetailView: View {
    @Environment(\.appUILanguage) var language
    @AppStorage(AISettingsKeys.providerID) var providerID = "openai"
    @State var baseURL = ""
    @State var model = ""
    @State var apiKey = ""
    @State var availableModels: [String] = []
    @State var status: AIConnectionStatus = .idle
    @State var isTestingConnection = false
    @State var isTestingFunction = false
    @State var isFetchingModels = false
    @State var targetLanguage = AIPromptSettings.defaultTargetLanguage
    @State var promptTemplate = AIPromptSettings.defaultTemplate
    @State private var didLoadProviderSettings = false
    @State private var didLoadPromptSettings = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                providerSection
                if selectedPreset.format.usesCodexExecutable {
                    codexSection
                    modelSection
                } else {
                    endpointSection
                    modelSection
                }
                promptSection
                validationSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TokyoNight.backgroundColor)
        .background(SettingsScrollChromeConfigurator())
        .onAppear {
            loadProviderSettings(for: providerID, allowsLegacyFallback: true)
            loadPromptSettings()
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
        .onChange(of: targetLanguage) { _, _ in
            guard didLoadPromptSettings else { return }
            savePromptSettings()
        }
        .onChange(of: promptTemplate) { _, _ in
            guard didLoadPromptSettings else { return }
            savePromptSettings()
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
        return trimmed.isEmpty ? language.text(.notSet) : trimmed
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
        case .codexCLI:
            return configuration.codexExecutablePath
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
                Text(language.text(.ai))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Text(language.text(.aiHeaderSubtitle))
                    .font(.system(size: 12.5))
                    .foregroundStyle(TokyoNight.mutedColor)
            }

            Spacer()
        }
    }

    private var providerSection: some View {
        SettingsPanel(title: language.text(.provider), systemImage: "building.2") {
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
        SettingsPanel(title: language.text(.endpoint), systemImage: "network") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledSettingsField(title: language.text(.baseURL)) {
                    StyledTextField(
                        text: $baseURL,
                        placeholder: selectedPreset.baseURL,
                        systemImage: "link"
                    )
                }

                LabeledSettingsField(title: language.text(.apiKey)) {
                    StyledSecureField(
                        text: $apiKey,
                        placeholder: selectedPreset.id == "anthropic" ? "sk-ant-..." : "sk-..."
                    )
                }
            }
        }
    }

    private var codexSection: some View {
        SettingsPanel(title: language.text(.codex), systemImage: "terminal") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledSettingsField(title: language.text(.executable)) {
                    StyledTextField(
                        text: $baseURL,
                        placeholder: selectedPreset.baseURL,
                        systemImage: "terminal"
                    )
                }

                LabeledSettingsField(title: language.text(.profile)) {
                    StyledTextField(
                        text: $apiKey,
                        placeholder: language.text(.useDefaultProfile),
                        systemImage: "person.crop.circle"
                    )
                }
            }
        }
    }

    private var modelFieldTitle: String {
        selectedPreset.format.usesCodexExecutable ? language.text(.modelOverride) : language.text(.currentModel)
    }

    private var modelFieldPlaceholder: String {
        if selectedPreset.format.usesCodexExecutable {
            return language.text(.useCodexDefault)
        }
        return selectedPreset.defaultModel
    }

    private var modelSection: some View {
        SettingsPanel(title: language.text(.model), systemImage: "cpu") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledSettingsField(title: modelFieldTitle) {
                    StyledTextField(
                        text: $model,
                        placeholder: modelFieldPlaceholder,
                        systemImage: "cube"
                    )
                }

                HStack(spacing: 10) {
                    Button {
                        fetchModels()
                    } label: {
                        Label(isFetchingModels ? language.text(.fetching) : language.text(.fetchModels), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SettingsActionButtonStyle())
                    .disabled(isBusy)

                    Text(modelsSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(TokyoNight.mutedColor)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                }

                if !availableModels.isEmpty {
                    ModelChoiceGrid(models: availableModels, selection: $model)
                }
            }
        }
    }

    private var promptSection: some View {
        SettingsPanel(title: language.text(.prompt), systemImage: "text.bubble") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledSettingsField(title: language.text(.promptTargetLanguage)) {
                    StyledTextField(
                        text: $targetLanguage,
                        placeholder: AIPromptSettings.defaultTargetLanguage,
                        systemImage: "globe"
                    )
                }

                LabeledSettingsField(title: language.text(.promptTemplate)) {
                    StyledPromptEditor(text: $promptTemplate)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "curlybraces")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TokyoNight.cyanColor)

                        Text(language.text(.promptVariables))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(TokyoNight.mutedColor)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 8)], spacing: 8) {
                        ForEach(AIPromptSettings.variableDescriptions) { variable in
                            PromptVariableChip(variable: variable)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        resetPromptSettings()
                    } label: {
                        Label(language.text(.promptReset), systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(SettingsActionButtonStyle())

                    Text(language.text(.promptVariablesHint))
                        .font(.system(size: 12))
                        .foregroundStyle(TokyoNight.mutedColor)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                }
            }
        }
    }

    private var validationSection: some View {
        SettingsPanel(title: language.text(.validation), systemImage: "checkmark.seal") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Button {
                        testConnection()
                    } label: {
                        Label(isTestingConnection ? language.text(.testing) : connectionTestTitle, systemImage: connectionTestIcon)
                    }
                    .buttonStyle(SettingsActionButtonStyle())
                    .disabled(isBusy)

                    Button {
                        testFunction()
                    } label: {
                        Label(isTestingFunction ? language.text(.testing) : language.text(.testModel), systemImage: "sparkles")
                    }
                    .buttonStyle(SettingsPrimaryButtonStyle())
                    .disabled(isBusy)

                    Spacer()
                }

                AIConnectionStatusRow(status: status, isBusy: isBusy)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(diagnosticRows, id: \.title) { row in
                        diagnosticRow(row.title, row.value)
                    }
                    diagnosticRow(language.text(.selected), trimmedModelText)
                }
                .padding(.top, 2)
            }
        }
    }

    var modelsSummary: String {
        if isFetchingModels {
            return language.text(.fetchingModelsFrom(selectedPreset.name))
        }

        if availableModels.isEmpty {
            return selectedPreset.format.usesCodexExecutable
                ? language.text(.modelOverrideHint)
                : language.text(.modelChoicesHint)
        }

        return language.text(.modelsLoaded(availableModels.count))
    }

    var connectionTestTitle: String {
        selectedPreset.format.usesCodexExecutable ? language.text(.testCodex) : language.text(.testEndpoint)
    }

    var connectionTestIcon: String {
        selectedPreset.format.usesCodexExecutable ? "terminal" : "point.3.connected.trianglepath.dotted"
    }

    var diagnosticRows: [(title: String, value: String)] {
        if selectedPreset.format.usesCodexExecutable {
            return [
                (language.text(.command), baseURL.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? selectedPreset.baseURL),
                (language.text(.profile), apiKey.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? language.text(.defaultStatus))
            ]
        }

        return [
            (language.text(.diagnosticsRequest), chatEndpointText),
            (language.text(.diagnosticsModels), modelsEndpointText)
        ]
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
        if !preset.format.usesCodexExecutable {
            defaults.set(baseURL, forKey: AISettingsKeys.baseURL)
            defaults.set(model, forKey: AISettingsKeys.model)
            defaults.set(apiKey, forKey: AISettingsKeys.apiKey)
        }
    }

    private func loadPromptSettings() {
        didLoadPromptSettings = false
        let configuration = AIPromptSettings.current()
        targetLanguage = configuration.targetLanguage
        promptTemplate = configuration.template
        didLoadPromptSettings = true
    }

    private func savePromptSettings() {
        AIPromptSettings.save(
            AIPromptConfiguration(
                targetLanguage: targetLanguage,
                template: promptTemplate
            )
        )
    }

    private func resetPromptSettings() {
        didLoadPromptSettings = false
        AIPromptSettings.reset()
        targetLanguage = AIPromptSettings.defaultTargetLanguage
        promptTemplate = AIPromptSettings.defaultTemplate
        didLoadPromptSettings = true
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

private struct StyledPromptEditor: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(TokyoNight.foregroundColor)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .focused($isFocused)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(minHeight: 260)
            .background(TokyoNight.backgroundDeepColor.opacity(0.92), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isFocused ? TokyoNight.cyanColor.opacity(0.72) : TokyoNight.borderColor.opacity(0.75), lineWidth: 1)
            }
    }
}

private struct PromptVariableChip: View {
    let variable: AIPromptVariableDescription

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("{{\(variable.name)}}")
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(TokyoNight.foregroundColor)
                .lineLimit(1)

            Text(variable.description)
                .font(.system(size: 10.5))
                .foregroundStyle(TokyoNight.mutedColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 52, alignment: .topLeading)
        .background(TokyoNight.backgroundDeepColor.opacity(0.62), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(TokyoNight.borderColor.opacity(0.48), lineWidth: 1)
        }
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
    @Environment(\.appUILanguage) private var language
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

                    Text(preset.localizedSummary(language: language))
                        .font(.system(size: 11.5))
                        .foregroundStyle(TokyoNight.mutedColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TokyoNight.cyanColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 50)
            .background(isSelected ? TokyoNight.selectionColor.opacity(0.58) : TokyoNight.backgroundDeepColor.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? TokyoNight.cyanColor.opacity(0.58) : TokyoNight.borderColor.opacity(0.52), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension AIProviderPreset {
    func localizedSummary(language: AppUILanguage) -> String {
        switch language {
        case .english:
            return summary
        case .chinese:
            switch id {
            case "openai":
                return "OpenAI 官方 API。"
            case "deepseek":
                return "使用 DeepSeek 的 OpenAI 兼容 API。"
            case "anthropic":
                return "Claude 官方 API。"
            case "codex-cli":
                return "使用本地 Codex，支持私密的流式解释。"
            default:
                return "任意 OpenAI 兼容端点。"
            }
        }
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 30)
                    .background(selection == model ? TokyoNight.selectionColor.opacity(0.5) : TokyoNight.backgroundDeepColor.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(selection == model ? TokyoNight.cyanColor.opacity(0.55) : TokyoNight.borderColor.opacity(0.45), lineWidth: 1)
                    }
                    .contentShape(Rectangle())
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
