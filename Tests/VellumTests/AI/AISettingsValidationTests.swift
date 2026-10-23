import Testing
@testable import VellumCore

@MainActor
@Suite("AI settings validation")
struct AISettingsValidationTests {
    @Test
    func newerRequestCancelsSuspendedWorkAndStaleCompletionKeepsItsTask() async throws {
        let validation = AISettingsValidation()
        defer { validation.invalidate() }
        var oldStarted = false
        var oldCancelled = false
        validation.start { request in
            oldStarted = true
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                oldCancelled = Task.isCancelled
                validation.finish(request, status: .failure("Old request cancelled"))
            }
        }
        try await waitForTestCondition("The original request started") { oldStarted }

        var newStarted = false
        var newCancelled = false
        let newRequest = validation.start(fetchingModels: true) { request in
            newStarted = true
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                newCancelled = Task.isCancelled
                validation.finish(request, status: .failure("New request cancelled"))
            }
        }
        try await waitForTestCondition("The replacement started and cancelled the original") {
            oldCancelled && newStarted
        }
        #expect(validation.isCurrent(newRequest))
        #expect(validation.isFetchingModels)
        #expect(validation.notification == nil)

        validation.invalidate()
        try await waitForTestCondition("The replacement task is still owned and can be cancelled") { newCancelled }
        #expect(validation.status == .idle)
        #expect(!validation.isFetchingModels)
        #expect(validation.notification == nil)
    }

    @Test
    func invalidatingModelTestCancelsWorkWithoutClearingCatalog() async throws {
        let validation = AISettingsValidation()
        defer { validation.invalidate() }
        let catalogRequest = validation.begin(fetchingModels: true)
        validation.finish(catalogRequest, status: .success("Catalog"), models: ["current-model"])
        var started = false
        var cancelled = false
        validation.start { request in
            started = true
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                cancelled = Task.isCancelled
                validation.finish(request, status: .failure("Cancelled model test"))
            }
        }
        try await waitForTestCondition("The model test started") { started }

        validation.invalidate(clearModels: false)
        try await waitForTestCondition("Model edits cancel the model test") { cancelled }
        #expect(validation.status == .idle)
        #expect(!validation.isTesting)
        #expect(validation.availableModels == ["current-model"])
    }

    @Test
    func startedRequestPublishesCompletedResultAndClearsBusyState() async throws {
        let validation = AISettingsValidation()
        let request = validation.start(fetchingModels: true) { request in
            await nextTestMainQueueTurn()
            validation.finish(request, status: .success("Catalog"), models: ["current-model"])
        }
        #expect(validation.isFetchingModels)
        try await waitForTestCondition("The owned request finished") { !validation.isFetchingModels }

        #expect(!validation.isCurrent(request))
        #expect(!validation.isTesting)
        #expect(validation.status == .success("Catalog"))
        #expect(validation.availableModels == ["current-model"])
        #expect(validation.notification?.text == "Catalog")
        #expect(validation.notification?.kind == .success)
    }

    @Test
    func invalidatedRequestCannotPublishOldModelsOrStatus() {
        let validation = AISettingsValidation()
        let request = validation.begin(fetchingModels: true)
        validation.invalidate()

        validation.finish(request, status: .success("Old provider"), models: ["old-model"])

        #expect(validation.availableModels.isEmpty)
        #expect(validation.status == .idle)
        #expect(!validation.isFetchingModels)
        #expect(validation.notification == nil)
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
        #expect(validation.notification == nil)

        validation.finish(newRequest, status: .success("Current provider"), models: ["current-model"])
        let currentNotification = validation.notification
        validation.finish(oldRequest, status: .success("Old endpoint"))
        #expect(validation.status == .success("Current provider"))
        #expect(validation.notification == currentNotification)
        #expect(validation.availableModels == ["current-model"])
        #expect(!validation.isFetchingModels)
        #expect(!validation.isTesting)
    }

    @Test
    func repeatedResultsEmitFreshNotificationsAndInvalidationClearsThem() {
        let validation = AISettingsValidation()
        let firstRequest = validation.begin()
        validation.finish(firstRequest, status: .failure("Endpoint unavailable"))
        let firstNotification = validation.notification
        #expect(firstNotification?.text == "Endpoint unavailable")
        #expect(firstNotification?.kind == .error)

        let retry = validation.begin()
        #expect(validation.notification == nil)
        validation.finish(retry, status: .failure("Endpoint unavailable"))
        #expect(validation.notification?.text == firstNotification?.text)
        #expect(validation.notification?.id != firstNotification?.id)

        validation.invalidate()
        #expect(validation.notification == nil)
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
    func editingModelDoesNotRestartIndependentCatalogRead() async throws {
        let validation = AISettingsValidation()
        defer { validation.invalidate() }
        var started = false
        var cancelled = false
        let request = validation.start(fetchingModels: true) { request in
            started = true
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                cancelled = Task.isCancelled
                validation.finish(request, status: .failure("Cancelled catalog"))
            }
        }
        try await waitForTestCondition("The catalog request started") { started }

        validation.invalidate(clearModels: false)
        await nextTestMainQueueTurn()
        #expect(validation.isCurrent(request))
        #expect(validation.isFetchingModels)
        #expect(!cancelled)

        validation.invalidate()
        try await waitForTestCondition("Changing providers cancels the catalog request") { cancelled }
        #expect(validation.status == .idle)
    }

    @Test(arguments: [
        ("codex-model", "xhigh" as String?, "xhigh" as String?),
        ("codex-model", nil, nil),
        ("custom-model", "xhigh", nil),
        ("", "medium", nil)
    ])
    func depthValidationRequiresExplicitKnownModelAndUnsupportedEffort(
        model: String, effort: String?, unsupported: String?
    ) throws {
        let validation = AISettingsValidation()
        let request = validation.begin(fetchingModels: true)
        validation.finish(request, status: .success("Settings loaded"), codexSettings: codexSettings)
        let configuration = try AIConfiguration(
            baseURLString: "/usr/local/bin/codex",
            model: model,
            apiKey: "",
            providerFormat: .codexCLI,
            reasoningEffort: effort
        )

        #expect(validation.unsupportedReasoningEffort(configuration: configuration) == unsupported)
        #expect(configuration.reasoningEffort == effort)
        if model == "custom-model" || model.isEmpty {
            #expect(validation.codexSettings?.model(for: configuration) == nil)
        }
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
