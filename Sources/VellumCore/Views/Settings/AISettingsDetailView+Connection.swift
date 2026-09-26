import SwiftUI

@MainActor
final class AISettingsValidation: ObservableObject {
    @Published var status: AIConnectionStatus = .idle
    @Published private(set) var availableModels: [String] = []
    @Published private(set) var isTesting = false
    @Published private(set) var isFetchingModels = false
    private var requestID: UUID?

    func begin(fetchingModels: Bool = false) -> UUID {
        let id = UUID()
        requestID = id
        isTesting = !fetchingModels
        isFetchingModels = fetchingModels
        return id
    }

    func isCurrent(_ id: UUID) -> Bool {
        requestID == id
    }

    func finish(_ id: UUID, status: AIConnectionStatus, models: [String]? = nil) {
        guard isCurrent(id) else { return }
        requestID = nil
        self.status = status
        if let models { availableModels = models }
        isTesting = false
        isFetchingModels = false
    }

    func invalidate(clearModels: Bool = true) {
        requestID = nil
        status = .idle
        isTesting = false
        isFetchingModels = false
        if clearModels { availableModels.removeAll() }
    }
}

extension AIProviderSettingsDetailView {
    func testConnection() {
        let requestID = validation.begin()

        Task { @MainActor in
            guard validation.isCurrent(requestID) else { return }
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
        let requestID = validation.begin(fetchingModels: true)

        Task { @MainActor in
            guard validation.isCurrent(requestID) else { return }
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
        let requestID = validation.begin()

        Task { @MainActor in
            guard validation.isCurrent(requestID) else { return }
            do {
                let configuration = try currentConfiguration(requireModel: !selectedPreset.format.usesCodexExecutable)
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
        let requestID = validation.begin(fetchingModels: true)

        Task { @MainActor in
            guard validation.isCurrent(requestID) else { return }
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
