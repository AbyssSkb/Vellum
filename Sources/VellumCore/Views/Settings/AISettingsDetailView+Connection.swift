import SwiftUI

extension AISettingsDetailView {
    func testConnection() {
        isTestingConnection = true

        Task { @MainActor in
            defer { isTestingConnection = false }

            do {
                let configuration = try currentConfiguration(requireModel: false)
                status = .working("Checking endpoint...")
                let message = try await AIExplanationClient.testConnection(configuration: configuration)
                status = .success(message)
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }

    func testFunction() {
        isTestingFunction = true

        Task { @MainActor in
            defer { isTestingFunction = false }

            do {
                let configuration = try currentConfiguration(requireModel: true)
                status = .working("Asking \(configuration.model)...")
                let message = try await AIExplanationClient.testFunction(configuration: configuration)
                status = .success(message)
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
