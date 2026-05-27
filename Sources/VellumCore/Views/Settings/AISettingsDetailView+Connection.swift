import SwiftUI

extension AISettingsDetailView {
    func testConnection() {
        isTestingConnection = true

        Task { @MainActor in
            defer { isTestingConnection = false }

            do {
                let configuration = try currentConfiguration(requireModel: true)
                status = .working("Testing \(configuration.model)...")
                _ = try await AIExplanationClient.testConnection(configuration: configuration)
                status = .success("Model ready: \(configuration.model)")
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }

    func fetchModels() {
        isFetchingModels = true

        Task { @MainActor in
            defer { isFetchingModels = false }

            do {
                let configuration = try currentConfiguration(requireModel: false)
                status = .working("Fetching models...")
                availableModels = try await AIExplanationClient.fetchModels(configuration: configuration)
                status = availableModels.isEmpty
                    ? .success("Connected. No models returned.")
                    : .success("\(availableModels.count) models loaded.")
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }
}
