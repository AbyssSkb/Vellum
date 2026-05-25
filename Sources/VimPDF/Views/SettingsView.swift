@preconcurrency import AppKit
import SwiftUI


struct AISettingsView: View {
    @State private var selectedCategory: SettingsCategory = .ai

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selectedCategory: $selectedCategory)
                .frame(width: 190)

            TokyoNightDivider(axis: .vertical)

            Group {
                switch selectedCategory {
                case .ai:
                    AISettingsDetailView()
                case .shortcuts:
                    ShortcutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 840, height: 560)
        .background(TokyoNight.backgroundColor)
        .preferredColorScheme(.dark)
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
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SettingsGroup(title: "Provider") {
                        SettingsRow(title: "Base URL", systemImage: "link") {
                            SettingsInputContainer {
                                TextField(AIConfiguration.defaultBaseURL, text: $baseURL)
                                    .textFieldStyle(.plain)
                            }
                            .frame(width: 360)
                        }

                        SettingsRow(title: "API Key", systemImage: "key") {
                            SettingsInputContainer {
                                SecureField("sk-...", text: $apiKey)
                                    .textFieldStyle(.plain)
                            }
                            .frame(width: 360)
                        }
                    }

                    SettingsGroup(title: "Model") {
                        SettingsRow(title: "Model", systemImage: "cube.transparent") {
                            ModelPickerField(
                                text: $model,
                                models: availableModels,
                                placeholder: AIConfiguration.defaultModel
                            )
                            .frame(width: 360)
                        }

                        SettingsRow(title: "Connection", systemImage: "circle.hexagongrid") {
                            AIConnectionLight(status: status, isBusy: isBusy)

                            Spacer(minLength: 12)

                            Button {
                                fetchModels()
                            } label: {
                                Label(isFetchingModels ? "Fetching" : "Fetch", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(SettingsActionButtonStyle())
                            .disabled(isBusy)

                            Button {
                                testConnection()
                            } label: {
                                Label(isTestingConnection ? "Testing" : "Test", systemImage: "checkmark.circle")
                            }
                            .buttonStyle(SettingsActionButtonStyle(accentColor: TokyoNight.blue))
                            .disabled(isBusy)
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
            }
        }
        .background(TokyoNight.backgroundColor)
        .onChange(of: apiKey) { _, _ in
            status = .idle
        }
        .onChange(of: baseURL) { _, _ in
            availableModels.removeAll()
            status = .idle
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Text("OpenAI-compatible provider and model")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TokyoNight.mutedColor)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(TokyoNight.backgroundColor)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TokyoNight.borderColor.opacity(0.26))
                .frame(height: 1)
        }
    }

    private var isBusy: Bool {
        isTestingConnection || isFetchingModels
    }

    private func testConnection() {
        isTestingConnection = true
        status = .working("Testing model...")

        Task { @MainActor in
            defer { isTestingConnection = false }

            do {
                let configuration = try currentConfiguration(requireModel: true)
                _ = try await AIExplanationClient.testConnection(configuration: configuration)
                status = .success("Model ready")
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }

    private func fetchModels() {
        isFetchingModels = true
        status = .working("Fetching models...")

        Task { @MainActor in
            defer { isFetchingModels = false }

            do {
                let configuration = try currentConfiguration(requireModel: false)
                let models = try await AIExplanationClient.fetchModels(configuration: configuration)
                availableModels = models

                let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
                if let firstModel = models.first,
                   trimmedModel.isEmpty || !models.contains(model) {
                    model = firstModel
                }

                status = models.isEmpty
                    ? .success("Connected. No models returned.")
                    : .success("\(models.count) models loaded.")
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }

    private func currentConfiguration(requireModel: Bool) throws -> AIConfiguration {
        return try AIConfiguration.current(requireModel: requireModel)
    }
}

