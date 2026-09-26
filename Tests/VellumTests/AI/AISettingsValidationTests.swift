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
}
