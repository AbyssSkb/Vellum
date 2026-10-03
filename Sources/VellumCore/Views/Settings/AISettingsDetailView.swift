import SwiftUI

enum AISettingsConfigurationPage: String, CaseIterable, Identifiable {
    case explanation
    case conversation

    var id: String { rawValue }

    var profile: AIConfigurationProfile {
        switch self {
        case .explanation:
            return .explanation
        case .conversation:
            return .conversation
        }
    }

    var promptProfile: AIPromptProfile {
        switch self {
        case .explanation:
            return .explanation
        case .conversation:
            return .conversation
        }
    }

    var systemImage: String {
        switch self {
        case .explanation:
            return "text.bubble"
        case .conversation:
            return "bubble.left.and.bubble.right"
        }
    }

    func title(language: AppUILanguage) -> String {
        switch self {
        case .explanation:
            return language.text(.aiExplanation)
        case .conversation:
            return language.text(.aiConversation)
        }
    }

    func subtitle(language: AppUILanguage) -> String {
        switch self {
        case .explanation:
            return language.text(.aiExplanationHeaderSubtitle)
        case .conversation:
            return language.text(.aiConversationHeaderSubtitle)
        }
    }
}

struct AIProviderSettingsDetailView: View {
    @Environment(\.appUILanguage) var language
    @State var providerID = "openai"
    @State var baseURL = ""
    @State var apiKey = ""
    @StateObject var validation = AISettingsValidation()
    @State private var didLoadProviderSettings = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                providerSection
                if selectedPreset.format.usesCodexExecutable {
                    codexSection
                } else {
                    endpointSection
                }
                validationSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TokyoNight.backgroundColor)
        .background(SettingsScrollChromeConfigurator())
        .onAppear {
            loadProviderSelection()
        }
        .onDisappear {
            validation.invalidate()
        }
        .onChange(of: providerID) { _, newValue in
            loadProviderSettings(for: newValue)
        }
        .onChange(of: apiKey) { _, _ in
            guard didLoadProviderSettings else { return }
            saveProviderSettings()
            validation.invalidate()
        }
        .onChange(of: baseURL) { _, _ in
            guard didLoadProviderSettings else { return }
            saveProviderSettings()
            validation.invalidate()
        }
    }

    var isBusy: Bool {
        validation.isTesting || validation.isFetchingModels
    }

    var selectedPreset: AIProviderPreset {
        AIProviderPreset.preset(for: providerID)
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
        SettingsHeader(
            title: language.text(.aiProviders),
            subtitle: language.text(.aiProvidersHeaderSubtitle),
            systemImage: "building.2"
        )
    }

    private var providerSection: some View {
        SettingsPanel(title: language.text(.provider), systemImage: "building.2") {
            VStack(alignment: .leading, spacing: 0) {
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

    private var validationSection: some View {
        SettingsPanel(title: language.text(.validation), systemImage: "checkmark.seal") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Button {
                        testConnection()
                    } label: {
                        Label(validation.isTesting ? language.text(.testing) : connectionTestTitle, systemImage: connectionTestIcon)
                    }
                    .buttonStyle(SettingsActionButtonStyle())
                    .disabled(isBusy)

                    Button {
                        fetchModels()
                    } label: {
                        Label(validation.isFetchingModels ? language.text(.fetching) : language.text(.fetchModels), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SettingsActionButtonStyle())
                    .disabled(isBusy)

                    Text(modelsSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(TokyoNight.mutedColor)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                }

                AIConnectionStatusRow(status: validation.status, isBusy: isBusy)

                if !validation.availableModels.isEmpty {
                    ModelPreviewGrid(models: validation.availableModels)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(diagnosticRows, id: \.title) { row in
                        diagnosticRow(row.title, row.value)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    var modelsSummary: String {
        if validation.isFetchingModels {
            return language.text(.fetchingModelsFrom(selectedPreset.name))
        }

        if validation.availableModels.isEmpty {
            return selectedPreset.format.usesCodexExecutable
                ? language.text(.providerModelsHint)
                : language.text(.providerModelsHint)
        }

        return language.text(.modelsLoaded(validation.availableModels.count))
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
                .font(.system(size: 11, weight: .regular))
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
            model: selectedPreset.defaultModel,
            apiKey: apiKey,
            providerFormat: selectedPreset.format,
            requireModel: requireModel
        )
    }

    private func loadProviderSelection() {
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: AISettingsKeys.providerSettingsSelectionID)
            ?? defaults.string(forKey: AISettingsKeys.providerID)
            ?? defaults.string(forKey: AISettingsKeys.conversationProviderID)
            ?? AIProviderPreset.presets.first?.id
            ?? AIProviderPreset.customID
        loadProviderSettings(for: id)
    }

    private func loadProviderSettings(for id: String) {
        let preset = AIProviderPreset.preset(for: id)
        let defaults = UserDefaults.standard
        AIConfiguration.migrateLegacyProviderSettings(defaults: defaults)
        didLoadProviderSettings = false
        providerID = preset.id
        baseURL = defaults.string(forKey: AISettingsKeys.baseURLKey(for: preset.id)) ?? preset.baseURL
        apiKey = defaults.string(forKey: AISettingsKeys.apiKeyKey(for: preset.id)) ?? ""
        validation.invalidate()
        didLoadProviderSettings = true
        saveProviderSettings()
    }

    private func saveProviderSettings() {
        let preset = selectedPreset
        let defaults = UserDefaults.standard
        defaults.set(preset.id, forKey: AISettingsKeys.providerSettingsSelectionID)
        defaults.set(baseURL, forKey: AISettingsKeys.baseURLKey(for: preset.id))
        defaults.set(apiKey, forKey: AISettingsKeys.apiKeyKey(for: preset.id))
    }
}

struct AISettingsDetailView: View {
    @Environment(\.appUILanguage) var language
    @AppStorage(AppPreferenceKeys.aiExplanationAutoPronunciationEnabled) private var autoPronunciationEnabled = false
    @AppStorage(AppPreferenceKeys.aiExplanationAutoPronunciationAccent) private var autoPronunciationAccent = AIPronunciationAccentPreference.american.rawValue
    let page: AISettingsConfigurationPage
    @State var providerID = "openai"
    @State var model = ""
    @StateObject var validation = AISettingsValidation()
    @State var targetLanguage = AIPromptSettings.defaultTargetLanguage
    @State var promptTemplate = AIPromptSettings.defaultTemplate
    @State private var didLoadProviderSettings = false
    @State private var didLoadPromptSettings = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                providerSection
                modelSection
                promptSection
                if page == .explanation {
                    pronunciationSection
                }
                validationSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TokyoNight.backgroundColor)
        .background(SettingsScrollChromeConfigurator())
        .onAppear {
            loadSettingsForCurrentPage()
            loadPromptSettings()
        }
        .onChange(of: page) { _, _ in
            loadSettingsForCurrentPage()
            loadPromptSettings()
        }
        .onDisappear {
            validation.invalidate()
        }
        .onChange(of: providerID) { _, newValue in
            loadProviderSelection(for: newValue)
        }
        .onChange(of: model) { _, _ in
            guard didLoadProviderSettings else { return }
            saveUsageSettings()
            validation.invalidate(clearModels: false)
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
        validation.isTesting || validation.isFetchingModels
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
        SettingsHeader(
            title: page.title(language: language),
            subtitle: page.subtitle(language: language),
            systemImage: page.systemImage
        )
    }

    private var providerSection: some View {
        SettingsPanel(title: language.text(.provider), systemImage: "building.2") {
            VStack(alignment: .leading, spacing: 0) {
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
                        Label(validation.isFetchingModels ? language.text(.fetching) : language.text(.fetchModels), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SettingsActionButtonStyle())
                    .disabled(isBusy)

                    Text(modelsSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(TokyoNight.mutedColor)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                }

                if !validation.availableModels.isEmpty {
                    ModelChoiceGrid(models: validation.availableModels, selection: $model)
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
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(TokyoNight.mutedColor)

                        Text(language.text(.promptVariables))
                            .font(.system(size: 11.5, weight: .regular))
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

    private var pronunciationSection: some View {
        SettingsPanel(title: language.text(.aiExplanationPronunciation), systemImage: "speaker.wave.2") {
            VStack(spacing: 0) {
                AIPronunciationToggleRow(
                    title: language.text(.aiExplanationAutoPronunciation),
                    subtitle: language.text(.aiExplanationAutoPronunciationSubtitle),
                    isOn: $autoPronunciationEnabled
                )

                if autoPronunciationEnabled {
                    AIPronunciationOptionRow(
                        title: language.text(.aiExplanationPronunciationAccent),
                        subtitle: language.text(.aiExplanationPronunciationAccentSubtitle)
                    ) {
                        AIPronunciationAccentSegmentedControl(
                            selection: $autoPronunciationAccent,
                            language: language
                        )
                    }
                }
            }
        }
    }

    private var validationSection: some View {
        SettingsPanel(title: language.text(.validation), systemImage: "checkmark.seal") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Button {
                        testFunction()
                    } label: {
                        Label(validation.isTesting ? language.text(.testing) : language.text(.testModel), systemImage: "sparkles")
                    }
                    .buttonStyle(SettingsPrimaryButtonStyle())
                    .disabled(isBusy)

                    Spacer()
                }

                AIConnectionStatusRow(status: validation.status, isBusy: isBusy)

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
        if validation.isFetchingModels {
            return language.text(.fetchingModelsFrom(selectedPreset.name))
        }

        if validation.availableModels.isEmpty {
            return selectedPreset.format.usesCodexExecutable
                ? language.text(.modelOverrideHint)
                : language.text(.modelChoicesHint)
        }

        return language.text(.modelsLoaded(validation.availableModels.count))
    }

    var diagnosticRows: [(title: String, value: String)] {
        if selectedPreset.format.usesCodexExecutable {
            return [
                (language.text(.command), (try? currentConfiguration(requireModel: false))?.codexExecutablePath ?? selectedPreset.baseURL),
                (language.text(.profile), (try? currentConfiguration(requireModel: false))?.codexProfile.nilIfEmpty ?? language.text(.defaultStatus))
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
                .font(.system(size: 11, weight: .regular))
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
        let defaults = UserDefaults.standard
        AIConfiguration.migrateLegacyProviderSettings(defaults: defaults)
        let baseURL = defaults.string(forKey: AISettingsKeys.baseURLKey(for: selectedPreset.id)) ?? selectedPreset.baseURL
        let apiKey = defaults.string(forKey: AISettingsKeys.apiKeyKey(for: selectedPreset.id)) ?? ""

        return try AIConfiguration(
            baseURLString: baseURL,
            model: model,
            apiKey: apiKey,
            providerFormat: selectedPreset.format,
            requireModel: requireModel
        )
    }

    private func loadSettingsForCurrentPage() {
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: page.profile.providerIDKey)
            ?? AIProviderPreset.presets.first?.id
            ?? AIProviderPreset.customID
        loadProviderSelection(for: id)
    }

    private func loadProviderSelection(for id: String) {
        let preset = AIProviderPreset.preset(for: id)
        let defaults = UserDefaults.standard
        AIConfiguration.migrateLegacyProviderSettings(defaults: defaults)
        didLoadProviderSettings = false
        providerID = preset.id
        model = defaults.string(forKey: page.profile.modelKey(for: preset.id)) ?? preset.defaultModel
        validation.invalidate()
        didLoadProviderSettings = true
        saveUsageSettings()
    }

    private func saveUsageSettings() {
        let preset = selectedPreset
        let defaults = UserDefaults.standard
        let profile = page.profile
        defaults.set(preset.id, forKey: profile.providerIDKey)
        defaults.set(preset.format.rawValue, forKey: profile.providerFormatKey)
        defaults.set(model, forKey: profile.modelKey(for: preset.id))
    }

    private func loadPromptSettings() {
        didLoadPromptSettings = false
        let configuration = AIPromptSettings.current(profile: page.promptProfile)
        targetLanguage = configuration.targetLanguage
        promptTemplate = configuration.template
        didLoadPromptSettings = true
    }

    private func savePromptSettings() {
        AIPromptSettings.save(
            AIPromptConfiguration(
                targetLanguage: targetLanguage,
                template: promptTemplate
            ),
            profile: page.promptProfile
        )
    }

    private func resetPromptSettings() {
        didLoadPromptSettings = false
        AIPromptSettings.reset(profile: page.promptProfile)
        targetLanguage = AIPromptSettings.defaultTargetLanguage
        promptTemplate = page.promptProfile.defaultTemplate
        didLoadPromptSettings = true
    }
}

private struct AIPronunciationToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TokyoNight.foregroundColor)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(TokyoNight.mutedColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                AISettingsTogglePill(isOn: isOn)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 58)
            .background(isHovered ? TokyoNight.panelColor : .clear)
            .overlay(alignment: .bottom) {
                TokyoNight.borderColor.opacity(0.45).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct AIPronunciationOptionRow<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(TokyoNight.mutedColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            content
        }
        .padding(.vertical, 12)
        .frame(minHeight: 58)
        .overlay(alignment: .bottom) {
            TokyoNight.borderColor.opacity(0.45).frame(height: 1)
        }
    }
}

private struct AIPronunciationAccentSegmentedControl: View {
    @Binding var selection: String
    let language: AppUILanguage

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AIPronunciationAccentPreference.allCases) { option in
                AIPronunciationSegmentButton(
                    title: option.title(language: language),
                    systemImage: option.systemImage,
                    isSelected: selection == option.rawValue
                ) {
                    selection = option.rawValue
                }
            }
        }
        .padding(3)
        .background(TokyoNight.backgroundDeepColor.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct AIPronunciationSegmentButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? TokyoNight.foregroundColor : TokyoNight.mutedColor)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(background, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isSelected ? TokyoNight.blueColor.opacity(0.5) : .clear, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var background: Color {
        if isSelected {
            return TokyoNight.panelElevatedColor
        }
        return isHovered ? TokyoNight.panelColor : .clear
    }
}

private struct AISettingsTogglePill: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isOn ? TokyoNight.blueColor : TokyoNight.panelElevatedColor)
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? TokyoNight.foregroundColor : TokyoNight.mutedColor)
                    .frame(width: 14, height: 14)
                    .padding(3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isOn ? TokyoNight.blueColor.opacity(0.65) : TokyoNight.borderColor.opacity(0.7), lineWidth: 1)
            }
    }
}

private struct SettingsHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(TokyoNight.mutedColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(TokyoNight.mutedColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.bottom, 4)
    }
}

private struct SettingsPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(TokyoNight.mutedColor)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LabeledSettingsField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TokyoNight.foregroundColor)

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
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(isFocused ? TokyoNight.blueColor : TokyoNight.mutedColor)
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
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(isFocused ? TokyoNight.blueColor : TokyoNight.mutedColor)
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
            .background(TokyoNight.panelColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isFocused ? TokyoNight.blueColor.opacity(0.8) : TokyoNight.borderColor.opacity(0.7), lineWidth: 1)
            }
    }
}

private struct PromptVariableChip: View {
    let variable: AIPromptVariableDescription

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("{{\(variable.name)}}")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(TokyoNight.foregroundColor)
                .lineLimit(1)

            Text(variable.description)
                .font(.system(size: 10.5))
                .foregroundStyle(TokyoNight.mutedColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 48, alignment: .topLeading)
    }
}

private extension View {
    func settingsInputChrome(isFocused: Bool) -> some View {
        self
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(TokyoNight.panelColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isFocused ? TokyoNight.blueColor.opacity(0.8) : TokyoNight.borderColor.opacity(0.7), lineWidth: 1)
            }
    }
}

private struct ProviderPresetRow: View {
    @Environment(\.appUILanguage) private var language
    let preset: AIProviderPreset
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.name)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(TokyoNight.foregroundColor)

                    Text(preset.localizedSummary(language: language))
                        .font(.system(size: 11.5))
                        .foregroundStyle(TokyoNight.mutedColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TokyoNight.blueColor)
                    .frame(width: 16)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 50)
            .background(isSelected ? TokyoNight.selectionColor : (isHovered ? TokyoNight.panelColor : .clear))
            .overlay(alignment: .bottom) {
                TokyoNight.borderColor.opacity(0.45).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
                return "DeepSeek API。"
            case "siliconflow":
                return "硅基流动 API。"
            case "anthropic":
                return "Claude 官方 API。"
            case "codex-cli":
                return "本地 Codex。"
            default:
                return "任意 OpenAI 兼容端点。"
            }
        }
    }
}

private struct ModelChoiceGrid: View {
    let models: [String]
    @Binding var selection: String
    @State private var hoveredModel: String?

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
                            .font(.system(size: 11.5, weight: selection == model ? .medium : .regular, design: .monospaced))
                            .foregroundStyle(TokyoNight.foregroundColor)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        if selection == model {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(TokyoNight.blueColor)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 30)
                    .background(selection == model || hoveredModel == model ? TokyoNight.panelElevatedColor : TokyoNight.panelColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(selection == model ? TokyoNight.blueColor.opacity(0.5) : TokyoNight.borderColor.opacity(hoveredModel == model ? 0.85 : 0.55), lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveredModel = $0 ? model : nil }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ModelPreviewGrid: View {
    let models: [String]

    private let columns = [
        GridItem(.adaptive(minimum: 180), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(models, id: \.self) { model in
                Text(model)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(TokyoNight.foregroundColor)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 30)
                    .background(TokyoNight.panelColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(TokyoNight.borderColor.opacity(0.45), lineWidth: 1)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsActionButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .regular))
            .foregroundStyle(TokyoNight.foregroundColor)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                configuration.isPressed
                ? TokyoNight.selectionColor.opacity(0.72)
                : (isHovered ? TokyoNight.panelElevatedColor : TokyoNight.panelColor),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(TokyoNight.borderColor.opacity(isHovered ? 0.9 : 0.65), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

private struct SettingsPrimaryButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(TokyoNight.backgroundDeepColor)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                configuration.isPressed
                ? TokyoNight.foregroundColor.opacity(0.8)
                : TokyoNight.foregroundColor.opacity(isHovered ? 1 : 0.92),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}
