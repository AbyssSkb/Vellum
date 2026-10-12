import SwiftUI

@MainActor
final class AISettingsValidation: ObservableObject {
    @Published var status: AIConnectionStatus = .idle
    @Published private(set) var availableModels: [String] = []
    @Published private(set) var codexSettings: CodexSettingsSnapshot?
    @Published private(set) var isTesting = false
    @Published private(set) var isFetchingModels = false
    private var requestID: UUID?
    private var requestTask: Task<Void, Never>?

    func begin(fetchingModels: Bool = false) -> UUID {
        requestTask?.cancel()
        requestTask = nil
        let id = UUID()
        requestID = id
        isTesting = !fetchingModels
        isFetchingModels = fetchingModels
        return id
    }

    @discardableResult
    func start(
        fetchingModels: Bool = false,
        operation: @escaping @MainActor (UUID) async -> Void
    ) -> UUID {
        let id = begin(fetchingModels: fetchingModels)
        requestTask = Task { @MainActor in
            guard isCurrent(id) else { return }
            await operation(id)
        }
        return id
    }

    func isCurrent(_ id: UUID) -> Bool {
        requestID == id
    }

    func finish(
        _ id: UUID,
        status: AIConnectionStatus,
        models: [String]? = nil,
        codexSettings: CodexSettingsSnapshot? = nil
    ) {
        guard isCurrent(id) else { return }
        requestID = nil
        requestTask = nil
        self.status = status
        if let models { availableModels = models }
        if let codexSettings { self.codexSettings = codexSettings }
        isTesting = false
        isFetchingModels = false
    }

    func invalidate(clearModels: Bool = true) {
        if !clearModels && isFetchingModels { return }
        requestTask?.cancel()
        requestTask = nil
        requestID = nil
        status = .idle
        isTesting = false
        isFetchingModels = false
        if clearModels {
            availableModels.removeAll()
            codexSettings = nil
        }
    }

    func unsupportedReasoningEffort(configuration: AIConfiguration) -> String? {
        guard configuration.providerFormat.usesCodexExecutable,
              let codexSettings,
              let model = codexSettings.model(for: configuration),
              let effort = configuration.reasoningEffort,
              !model.supportedReasoningEfforts.contains(effort) else { return nil }
        return effort
    }
}

extension AIProviderSettingsDetailView {
    func testConnection() {
        validation.start { requestID in
            do {
                let configuration = try currentConfiguration(requireModel: false)
                validation.status = .working(configuration.providerFormat.usesCodexExecutable ? language.text(.checkingCodex) : language.text(.checkingEndpoint))
                let message = try await AIExplanationClient.testConnection(configuration: configuration)
                validation.finish(requestID, status: .success(message))
            } catch {
                validation.finish(requestID, status: .failure(error.localizedDescription))
            }
        }
    }

    func fetchModels() {
        validation.start(fetchingModels: true) { requestID in
            do {
                let configuration = try currentConfiguration(requireModel: false)
                validation.status = .working(language.text(.fetchingModels))
                let models = try await AIExplanationClient.fetchModels(configuration: configuration)
                validation.finish(requestID, status: .success(models.isEmpty
                    ? language.text(.connectedNoModels)
                    : language.text(.modelsLoaded(models.count))), models: models)
            } catch {
                validation.finish(requestID, status: .failure(error.localizedDescription))
            }
        }
    }
}

extension AISettingsDetailView {
    func testFunction() {
        validation.start { requestID in
            do {
                let configuration = try currentConfiguration(requireModel: !selectedPreset.format.usesCodexExecutable)
                if let effort = validation.unsupportedReasoningEffort(configuration: configuration) {
                    validation.finish(requestID, status: .failure(language.text(.reasoningEffortUnsupported(effort))))
                    return
                }
                let target = configuration.providerFormat.usesCodexExecutable
                    ? "Codex"
                    : configuration.model
                validation.status = .working(language.text(.askingTarget(target)))
                let message = try await AIExplanationClient.testFunction(configuration: configuration)
                validation.finish(requestID, status: .success(message))
            } catch {
                validation.finish(requestID, status: .failure(error.localizedDescription))
            }
        }
    }

    func fetchModels() {
        validation.start(fetchingModels: true) { requestID in
            do {
                let configuration = try currentConfiguration(requireModel: false)
                validation.status = .working(language.text(.fetchingModels))
                let settings = configuration.providerFormat.usesCodexExecutable
                    ? try await CodexAppServerAIExplanationClient().fetchSettings(configuration: configuration)
                    : nil
                let models = if let settings {
                    settings.models.map(\.id)
                } else {
                    try await AIExplanationClient.fetchModels(configuration: configuration)
                }
                validation.finish(requestID, status: .success(models.isEmpty
                    ? language.text(.connectedNoModels)
                    : language.text(.modelsLoaded(models.count))), models: models, codexSettings: settings)
            } catch {
                validation.finish(requestID, status: .failure(error.localizedDescription))
            }
        }
    }
}
