import SwiftUI

extension AISettingsDetailView {
    func testConnection() {
        isTestingConnection = true

        Task { @MainActor in
            defer { isTestingConnection = false }

            do {
                let configuration = try currentConfiguration(requireModel: false)
                status = .working(configuration.providerFormat.usesCodexExecutable ? language.text(.checkingCodex) : language.text(.checkingEndpoint))
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
                let configuration = try currentConfiguration(requireModel: !selectedPreset.format.usesCodexExecutable)
                let target = configuration.providerFormat.usesCodexExecutable
                    ? "Codex"
                    : configuration.model
                status = .working(language.text(.askingTarget(target)))
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
                status = .working(language.text(.fetchingModels))
                availableModels = try await AIExplanationClient.fetchModels(configuration: configuration)
                status = availableModels.isEmpty
                    ? .success(language.text(.connectedNoModels))
                    : .success(language.text(.modelsLoaded(availableModels.count)))
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }
}
