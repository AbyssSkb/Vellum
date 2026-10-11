import Testing
@testable import VellumCore

@MainActor
@Suite("AI settings validation")
struct AISettingsValidationTests {
    @Test
    func invalidatedRequestCannotPublishOldModelsOrStatus() {
        let validation = AISettingsValidation()
        let request = validation.begin(fetchingModels: true)
        validation.invalidate()

        validation.finish(request, status: .success("Old provider"), models: ["old-model"])

        #expect(validation.availableModels.isEmpty)
        #expect(validation.status == .idle)
        #expect(!validation.isFetchingModels)
    }

    @Test
    func staleFailureCannotClearNewRequestOrReplaceItsResult() {
        let validation = AISettingsValidation()
        let oldRequest = validation.begin()
        validation.invalidate()
        let newRequest = validation.begin(fetchingModels: true)

        validation.finish(oldRequest, status: .failure("Old endpoint"))
        #expect(validation.isFetchingModels)
        #expect(validation.isCurrent(newRequest))

        validation.finish(newRequest, status: .success("Current provider"), models: ["current-model"])
        validation.finish(oldRequest, status: .success("Old endpoint"))
        #expect(validation.status == .success("Current provider"))
        #expect(validation.availableModels == ["current-model"])
        #expect(!validation.isFetchingModels)
        #expect(!validation.isTesting)
    }

    @Test
    func modelEditsInvalidateTestsWithoutClearingModelChoices() {
        let validation = AISettingsValidation()
        let modelsRequest = validation.begin(fetchingModels: true)
        validation.finish(modelsRequest, status: .success("Models loaded"), models: ["first", "second"])
        let testRequest = validation.begin()

        validation.invalidate(clearModels: false)
        validation.finish(testRequest, status: .success("Previous model works"))

        #expect(validation.availableModels == ["first", "second"])
        #expect(validation.status == .idle)
        #expect(!validation.isTesting)

        validation.invalidate()
        #expect(validation.availableModels.isEmpty)
    }

    @Test
    func invalidatedCodexSettingsCannotReplaceNewProviderCapabilities() {
        let validation = AISettingsValidation()
        let oldRequest = validation.begin(fetchingModels: true)
        validation.invalidate()
        let newRequest = validation.begin(fetchingModels: true)

        validation.finish(oldRequest, status: .success("Old settings"), codexSettings: codexSettings)
        #expect(validation.codexSettings == nil)
        #expect(validation.isCurrent(newRequest))

        validation.finish(newRequest, status: .success("Current settings"), codexSettings: codexSettings)
        #expect(validation.codexSettings == codexSettings)
    }

    @Test
    func modelAndDepthEditsKeepCatalogWhileProviderChangesClearIt() {
        let validation = AISettingsValidation()
        let request = validation.begin(fetchingModels: true)
        validation.finish(request, status: .success("Settings loaded"), codexSettings: codexSettings)

        validation.invalidate(clearModels: false)
        #expect(validation.codexSettings == codexSettings)

        validation.invalidate()
        #expect(validation.codexSettings == nil)
    }

    @Test
    func editingModelDoesNotRestartIndependentCatalogRead() {
        let validation = AISettingsValidation()
        let request = validation.begin(fetchingModels: true)

        validation.invalidate(clearModels: false)
        #expect(validation.isCurrent(request))
        #expect(validation.isFetchingModels)

        validation.finish(request, status: .success("Settings loaded"), codexSettings: codexSettings)
        #expect(validation.codexSettings == codexSettings)
    }

    @Test
    func unsupportedSavedDepthIsReportedWithoutChangingConfiguration() throws {
        let validation = AISettingsValidation()
        let request = validation.begin(fetchingModels: true)
        validation.finish(request, status: .success("Settings loaded"), codexSettings: codexSettings)
        let configuration = try AIConfiguration(
            baseURLString: "/usr/local/bin/codex",
            model: "codex-model",
            apiKey: "",
            providerFormat: .codexCLI,
            reasoningEffort: "xhigh"
        )

        #expect(validation.unsupportedReasoningEffort(configuration: configuration) == "xhigh")
        #expect(configuration.reasoningEffort == "xhigh")
    }

    @Test
    func lowLevelUnspecifiedDepthDoesNotInventAnInheritedSetting() throws {
        let validation = AISettingsValidation()
        let request = validation.begin(fetchingModels: true)
        validation.finish(request, status: .success("Settings loaded"), codexSettings: codexSettings)
        let configuration = try AIConfiguration(
            baseURLString: "/usr/local/bin/codex",
            model: "codex-model",
            apiKey: "",
            providerFormat: .codexCLI
        )

        #expect(validation.unsupportedReasoningEffort(configuration: configuration) == nil)
        #expect(configuration.reasoningEffort == nil)
    }

    @Test
    func unrecognizedModelDoesNotInventSupportedDepths() throws {
        let validation = AISettingsValidation()
        let request = validation.begin(fetchingModels: true)
        validation.finish(request, status: .success("Settings loaded"), codexSettings: codexSettings)
        let configuration = try AIConfiguration(
            baseURLString: "/usr/local/bin/codex",
            model: "custom-model",
            apiKey: "",
            providerFormat: .codexCLI,
            reasoningEffort: "xhigh"
        )

        #expect(validation.unsupportedReasoningEffort(configuration: configuration) == nil)
        #expect(validation.codexSettings?.model(for: configuration) == nil)
    }

    @Test
    func blankModelDoesNotUseCatalogDefaultForDepthValidation() throws {
        let validation = AISettingsValidation()
        let request = validation.begin(fetchingModels: true)
        validation.finish(request, status: .success("Models loaded"), codexSettings: codexSettings)
        let configuration = try AIConfiguration(
            baseURLString: "/usr/local/bin/codex",
            model: "",
            apiKey: "",
            providerFormat: .codexCLI,
            reasoningEffort: "medium"
        )
        #expect(validation.unsupportedReasoningEffort(configuration: configuration) == nil)
        #expect(validation.codexSettings?.model(for: configuration) == nil)
    }

    private var codexSettings: CodexSettingsSnapshot {
        CodexSettingsSnapshot(
            models: [CodexModelInfo(
                id: "codex-model",
                supportedReasoningEfforts: ["low", "high"]
            )]
        )
    }
}
