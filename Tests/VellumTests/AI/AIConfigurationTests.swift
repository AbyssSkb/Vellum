import Foundation
import Testing
@testable import VellumCore

@Suite("AI configuration")
struct AIConfigurationTests {
    @Test
    func currentConfigurationReadsSelectedProviderSettings() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults
        let providerID = "anthropic"
        defaults.set(providerID, forKey: AISettingsKeys.providerID)
        defaults.set("https://legacy.example.com/v1", forKey: AISettingsKeys.baseURL)
        defaults.set("legacy-model", forKey: AISettingsKeys.model)
        defaults.set("legacy-key", forKey: AISettingsKeys.apiKey)
        defaults.set("https://api.anthropic.com/v1", forKey: AISettingsKeys.baseURLKey(for: providerID))
        defaults.set("claude-test", forKey: AISettingsKeys.modelKey(for: providerID))
        defaults.set("anthropic-key", forKey: AISettingsKeys.apiKeyKey(for: providerID))

        let configuration = try AIConfiguration.current(defaults: defaults)

        #expect(configuration.baseURL.absoluteString == "https://api.anthropic.com/v1")
        #expect(configuration.model == "claude-test")
        #expect(configuration.apiKey == "anthropic-key")
        #expect(configuration.providerFormat == .anthropicMessages)
    }

    @Test
    func conversationConfigurationIsIndependentFromExplanationSettings() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults
        defaults.set("openai", forKey: AISettingsKeys.providerID)
        defaults.set("https://api.explain.example/v1", forKey: AISettingsKeys.baseURLKey(for: "openai"))
        defaults.set("explain-model", forKey: AISettingsKeys.modelKey(for: "openai"))
        defaults.set("explain-key", forKey: AISettingsKeys.apiKeyKey(for: "openai"))
        defaults.set("anthropic", forKey: AISettingsKeys.conversationProviderID)
        defaults.set("https://api.anthropic.com/v1", forKey: AISettingsKeys.baseURLKey(for: "anthropic"))
        defaults.set("shared-anthropic-key", forKey: AISettingsKeys.apiKeyKey(for: "anthropic"))
        defaults.set("chat-model", forKey: AISettingsKeys.conversationModelKey(for: "anthropic"))

        let explanation = try AIConfiguration.current(profile: .explanation, defaults: defaults)
        let conversation = try AIConfiguration.current(profile: .conversation, defaults: defaults)

        #expect(explanation.model == "explain-model")
        #expect(explanation.apiKey == "explain-key")
        #expect(explanation.providerFormat == .openAICompatible)
        #expect(conversation.model == "chat-model")
        #expect(conversation.apiKey == "shared-anthropic-key")
        #expect(conversation.providerFormat == .anthropicMessages)
    }

    @Test
    func conversationConfigurationFallsBackToLegacyConversationProviderSecrets() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults
        defaults.set("anthropic", forKey: AISettingsKeys.conversationProviderID)
        defaults.set("https://legacy-chat.example/v1", forKey: AISettingsKeys.conversationBaseURLKey(for: "anthropic"))
        defaults.set("chat-model", forKey: AISettingsKeys.conversationModelKey(for: "anthropic"))
        defaults.set("legacy-chat-key", forKey: AISettingsKeys.conversationAPIKeyKey(for: "anthropic"))

        let configuration = try AIConfiguration.current(profile: .conversation, defaults: defaults)

        #expect(configuration.baseURL.absoluteString == "https://legacy-chat.example/v1")
        #expect(configuration.model == "chat-model")
        #expect(configuration.apiKey == "legacy-chat-key")
    }

    @Test
    func codexCLIConfigurationUsesExecutablePathAndAllowsEmptySecrets() throws {
        let configuration = try AIConfiguration(
            baseURLString: "/opt/homebrew/bin/codex",
            model: "",
            apiKey: "",
            providerFormat: .codexCLI,
            requireModel: true
        )

        #expect(configuration.providerFormat == .codexCLI)
        #expect(configuration.codexExecutablePath == "/opt/homebrew/bin/codex")
        #expect(configuration.model == "")
        #expect(configuration.codexProfile == "")
    }

    @Test(arguments: [
        ("codex-cli", AIProviderFormat.codexCLI),
        ("siliconflow", AIProviderFormat.openAICompatible)
    ])
    func providerPresetsLoadUsableRuntimeConfigurations(id: String, format: AIProviderFormat) throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let preset = AIProviderPreset.preset(for: id)
        preferences.defaults.set(id, forKey: AISettingsKeys.providerID)
        preferences.defaults.set("test-key", forKey: AISettingsKeys.apiKeyKey(for: id))

        let configuration = try AIConfiguration.current(defaults: preferences.defaults)

        #expect(preset.id == id)
        #expect(configuration.providerFormat == format)
        #expect(configuration.model == preset.defaultModel)
        #expect(configuration.apiKey == "test-key")
        if format == .codexCLI {
            #expect(configuration.codexExecutablePath == preset.baseURL)
        } else {
            #expect(configuration.baseURL.absoluteString == preset.baseURL)
        }
    }
}
