@preconcurrency import AppKit
import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case ai
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ai:
            return "AI"
        case .shortcuts:
            return "Shortcuts"
        }
    }

    var subtitle: String {
        switch self {
        case .ai:
            return "Provider and model"
        case .shortcuts:
            return "Keyboard map"
        }
    }

    var systemImage: String {
        switch self {
        case .ai:
            return "sparkles"
        case .shortcuts:
            return "keyboard"
        }
    }
}

enum AIConnectionStatus: Equatable {
    case idle
    case working(String)
    case success(String)
    case failure(String)

    var text: String {
        switch self {
        case .idle:
            return "Not checked"
        case .working(let message), .success(let message), .failure(let message):
            return message
        }
    }

    var color: NSColor {
        switch self {
        case .idle:
            return TokyoNight.muted
        case .working:
            return TokyoNight.blue
        case .success:
            return NSColor(calibratedRed: 0.62, green: 0.86, blue: 0.49, alpha: 1)
        case .failure:
            return TokyoNight.red
        }
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}

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

struct SettingsSidebar: View {
    @Binding var selectedCategory: SettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("VimPDF")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(TokyoNight.foregroundColor)

                Text("Settings")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TokyoNight.mutedColor)
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 8)

            ForEach(SettingsCategory.allCases) { category in
                Button {
                    selectedCategory = category
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: category.systemImage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(selectedCategory == category ? TokyoNight.blueColor : TokyoNight.mutedColor)
                            .frame(width: 20)

                        Text(category.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TokyoNight.foregroundColor)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(selectedCategory == category ? TokyoNight.selectionColor.opacity(0.92) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(selectedCategory == category ? TokyoNight.blueColor.opacity(0.22) : Color.clear, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
            }

            Spacer()
        }
        .background {
            ZStack {
                SidebarVisualEffectBackground()
                TokyoNight.backgroundDeepColor.opacity(0.68)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(TokyoNight.borderColor.opacity(0.42))
                .frame(width: 1)
        }
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

