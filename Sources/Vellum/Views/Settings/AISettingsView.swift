@preconcurrency import AppKit
import SwiftUI

struct AISettingsView: View {
    var body: some View {
        TabView {
            AISettingsDetailView()
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }

            ShortcutSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(width: 620, height: 520)
    }
}

struct AISettingsDetailView: View {
    @AppStorage(AISettingsKeys.baseURL) private var baseURL = AIConfiguration.defaultBaseURL
    @AppStorage(AISettingsKeys.model) private var model = AIConfiguration.defaultModel
    @AppStorage(AISettingsKeys.apiKey) private var apiKey = ""
    @State private var availableModels: [String] = []
    @State private var status: AIConnectionStatus = .idle
    @State private var isTestingConnection = false
    @State private var isFetchingModels = false

    var body: some View {
        Form {
            Section {
                TextField("Base URL", text: $baseURL, prompt: Text(AIConfiguration.defaultBaseURL))
                    .textContentType(.URL)

                SecureField("API Key", text: $apiKey, prompt: Text("sk-..."))

                TextField("Model", text: $model, prompt: Text(AIConfiguration.defaultModel))
                    .textSelection(.enabled)
            } header: {
                Text("Provider")
            } footer: {
                Text("Use an OpenAI-compatible base URL, for example https://api.openai.com/v1.")
            }

            Section {
                HStack {
                    Button {
                        fetchModels()
                    } label: {
                        Label(isFetchingModels ? "Fetching Models" : "Fetch Models", systemImage: "arrow.clockwise")
                    }
                    .disabled(isBusy)

                    Button {
                        testConnection()
                    } label: {
                        Label(isTestingConnection ? "Testing" : "Test Connection", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
                }

                if !availableModels.isEmpty {
                    Picker("Fetched Models", selection: $model) {
                        ForEach(availableModels, id: \.self) { fetchedModel in
                            Text(fetchedModel).tag(fetchedModel)
                        }
                    }
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("Fetching models only fills this menu. It will not change the model unless you choose one.")
            }

            Section {
                StatusRow(status: status, isBusy: isBusy)

                LabeledContent("Chat Endpoint") {
                    Text(chatEndpointText)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Current Model") {
                    Text(trimmedModelText)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Diagnostics")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onChange(of: apiKey) { _, _ in
            status = .idle
        }
        .onChange(of: baseURL) { _, _ in
            availableModels.removeAll()
            status = .idle
        }
        .onChange(of: model) { _, _ in
            status = .idle
        }
    }

    private var isBusy: Bool {
        isTestingConnection || isFetchingModels
    }

    private var trimmedModelText: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not set" : trimmed
    }

    private var chatEndpointText: String {
        guard let configuration = try? currentConfiguration(requireModel: false) else {
            return "Invalid base URL"
        }
        return configuration.chatCompletionsURL.absoluteString
    }

    private func testConnection() {
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

    private func fetchModels() {
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

    private func currentConfiguration(requireModel: Bool) throws -> AIConfiguration {
        try AIConfiguration(
            baseURLString: baseURL,
            model: model,
            apiKey: apiKey,
            requireModel: requireModel
        )
    }
}

private struct StatusRow: View {
    let status: AIConnectionStatus
    let isBusy: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: status.systemImage)
                    .foregroundStyle(status.tint)
            }

            Text(status.text)
                .foregroundStyle(status.isIdle ? .secondary : .primary)
                .textSelection(.enabled)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
