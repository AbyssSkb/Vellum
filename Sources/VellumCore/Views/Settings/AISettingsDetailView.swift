import SwiftUI

struct AISettingsDetailView: View {
    @AppStorage(AISettingsKeys.baseURL) var baseURL = AIConfiguration.defaultBaseURL
    @AppStorage(AISettingsKeys.model) var model = AIConfiguration.defaultModel
    @AppStorage(AISettingsKeys.apiKey) var apiKey = ""
    @State var availableModels: [String] = []
    @State var status: AIConnectionStatus = .idle
    @State var isTestingConnection = false
    @State var isFetchingModels = false

    var body: some View {
        Form {
            providerSection
            connectionSection
            diagnosticsSection
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

    var isBusy: Bool {
        isTestingConnection || isFetchingModels
    }

    var trimmedModelText: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not set" : trimmed
    }

    var chatEndpointText: String {
        guard let configuration = try? currentConfiguration(requireModel: false) else {
            return "Invalid base URL"
        }
        return configuration.chatCompletionsURL.absoluteString
    }

    private var providerSection: some View {
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
    }

    private var connectionSection: some View {
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
    }

    private var diagnosticsSection: some View {
        Section {
            AIConnectionStatusRow(status: status, isBusy: isBusy)

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

    func currentConfiguration(requireModel: Bool) throws -> AIConfiguration {
        try AIConfiguration(
            baseURLString: baseURL,
            model: model,
            apiKey: apiKey,
            requireModel: requireModel
        )
    }
}
