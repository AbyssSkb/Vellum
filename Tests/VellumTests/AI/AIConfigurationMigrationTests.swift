import Foundation
import Testing
@testable import VellumCore

@Suite("AI provider configuration migration")
struct AIConfigurationMigrationTests {
    @Test
    func globalSettingsStayWithOriginalProviderAfterSwitching() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults
        defaults.set("deepseek", forKey: AISettingsKeys.providerID)
        defaults.set("anthropic", forKey: AISettingsKeys.providerSettingsSelectionID)
        defaults.set("anthropic", forKey: AISettingsKeys.conversationProviderID)
        defaults.set("https://original.example/v1", forKey: AISettingsKeys.baseURL)
        defaults.set("original-model", forKey: AISettingsKeys.model)
        defaults.set("original-key", forKey: AISettingsKeys.apiKey)

        do {
            _ = try AIConfiguration.current(profile: .conversation, defaults: defaults)
            Issue.record("The other provider must require its own API key")
        } catch AIExplanationError.missingAPIKey {
        } catch {
            Issue.record(error)
        }
        let original = try AIConfiguration.current(defaults: defaults)
        #expect(original.baseURL.absoluteString == "https://original.example/v1")
        #expect(original.model == "original-model")
        #expect(original.apiKey == "original-key")

        defaults.set("anthropic", forKey: AISettingsKeys.providerID)
        do {
            _ = try AIConfiguration.current(defaults: defaults)
            Issue.record("Switching providers must not copy the original API key")
        } catch AIExplanationError.missingAPIKey {
        } catch {
            Issue.record(error)
        }
        #expect(defaults.object(forKey: AISettingsKeys.baseURLKey(for: "anthropic")) == nil)
        #expect(defaults.object(forKey: AISettingsKeys.modelKey(for: "anthropic")) == nil)
        #expect(defaults.object(forKey: AISettingsKeys.apiKeyKey(for: "anthropic")) == nil)

        defaults.set("new-key", forKey: AISettingsKeys.apiKeyKey(for: "anthropic"))
        let selected = try AIConfiguration.current(defaults: defaults)
        let preset = AIProviderPreset.preset(for: "anthropic")
        #expect(selected.baseURL.absoluteString == preset.baseURL)
        #expect(selected.model == preset.defaultModel)
        #expect(selected.apiKey == "new-key")

        defaults.set("deepseek", forKey: AISettingsKeys.providerID)
        let restored = try AIConfiguration.current(defaults: defaults)
        #expect(restored.baseURL == original.baseURL)
        #expect(restored.model == original.model)
        #expect(restored.apiKey == original.apiKey)
        #expect(defaults.object(forKey: AISettingsKeys.baseURL) == nil)
        #expect(defaults.object(forKey: AISettingsKeys.model) == nil)
        #expect(defaults.object(forKey: AISettingsKeys.apiKey) == nil)
    }

    @Test(arguments: ["", "removed-provider"])
    func originalProviderUsesTheSameDefaultResolutionAsRuntime(providerID: String) throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults
        if !providerID.isEmpty {
            defaults.set(providerID, forKey: AISettingsKeys.providerID)
        }
        defaults.set("anthropic", forKey: AISettingsKeys.providerSettingsSelectionID)
        defaults.set("original-key", forKey: AISettingsKeys.apiKey)

        let configuration = try AIConfiguration.current(defaults: defaults)
        let owner = providerID.isEmpty ? "openai" : AIProviderPreset.customID
        #expect(configuration.apiKey == "original-key")
        #expect(defaults.string(forKey: AISettingsKeys.apiKeyKey(for: owner)) == "original-key")
        #expect(defaults.object(forKey: AISettingsKeys.apiKeyKey(for: "anthropic")) == nil)
    }

    @Test(arguments: ["", "saved"])
    func scopedSettingsIncludingEmptyValuesWinAndMigrationDoesNotRepeat(value: String) throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults
        defaults.set("anthropic", forKey: AISettingsKeys.providerID)
        let keys = [
            (AISettingsKeys.baseURL, AISettingsKeys.baseURLKey(for: "anthropic")),
            (AISettingsKeys.model, AISettingsKeys.modelKey(for: "anthropic")),
            (AISettingsKeys.apiKey, AISettingsKeys.apiKeyKey(for: "anthropic"))
        ]
        for (legacyKey, scopedKey) in keys {
            defaults.set("legacy", forKey: legacyKey)
            defaults.set(value, forKey: scopedKey)
        }
        defaults.set("legacy-chat-url", forKey: AISettingsKeys.conversationBaseURLKey(for: "anthropic"))
        defaults.set("legacy-chat-key", forKey: AISettingsKeys.conversationAPIKeyKey(for: "anthropic"))

        AIConfiguration.migrateLegacyProviderSettings(defaults: defaults)
        for (legacyKey, scopedKey) in keys {
            #expect(defaults.string(forKey: scopedKey) == value)
            #expect(defaults.object(forKey: legacyKey) == nil)
            defaults.removeObject(forKey: scopedKey)
        }
        AIConfiguration.migrateLegacyProviderSettings(defaults: defaults)
        for (_, scopedKey) in keys {
            #expect(defaults.object(forKey: scopedKey) == nil)
        }
    }

    @Test
    func conversationCredentialsMigrateForEveryProviderAndModelsStayIndependent() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults
        for preset in AIProviderPreset.presets {
            defaults.set("https://\(preset.id).example/v1", forKey: AISettingsKeys.conversationBaseURLKey(for: preset.id))
            defaults.set("\(preset.id)-key", forKey: AISettingsKeys.conversationAPIKeyKey(for: preset.id))
            defaults.set("\(preset.id)-chat", forKey: AISettingsKeys.conversationModelKey(for: preset.id))
        }

        AIConfiguration.migrateLegacyProviderSettings(defaults: defaults)
        for preset in AIProviderPreset.presets {
            #expect(defaults.string(forKey: AISettingsKeys.baseURLKey(for: preset.id)) == "https://\(preset.id).example/v1")
            #expect(defaults.string(forKey: AISettingsKeys.apiKeyKey(for: preset.id)) == "\(preset.id)-key")
            #expect(defaults.object(forKey: AISettingsKeys.conversationBaseURLKey(for: preset.id)) == nil)
            #expect(defaults.object(forKey: AISettingsKeys.conversationAPIKeyKey(for: preset.id)) == nil)
            #expect(defaults.string(forKey: AISettingsKeys.conversationModelKey(for: preset.id)) == "\(preset.id)-chat")
            #expect(defaults.object(forKey: AISettingsKeys.modelKey(for: preset.id)) == nil)
        }
    }

    @Test
    func blankLegacyValuesKeepPresetDefaults() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults
        defaults.set(" \n ", forKey: AISettingsKeys.baseURL)
        defaults.set(" \n ", forKey: AISettingsKeys.model)
        defaults.set(" \n ", forKey: AISettingsKeys.conversationBaseURLKey(for: "openai"))
        defaults.set(" \n ", forKey: AISettingsKeys.conversationAPIKeyKey(for: "openai"))
        defaults.set("current-key", forKey: AISettingsKeys.apiKeyKey(for: "openai"))

        let configuration = try AIConfiguration.current(defaults: defaults)
        let preset = AIProviderPreset.preset(for: "openai")
        #expect(configuration.baseURL.absoluteString == preset.baseURL)
        #expect(configuration.model == preset.defaultModel)
        #expect(configuration.apiKey == "current-key")
    }

    @Test
    func globalOwnerCredentialsHaveConsistentPrecedenceWhenConversationLoadsFirst() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults
        defaults.set("anthropic", forKey: AISettingsKeys.providerID)
        defaults.set("anthropic", forKey: AISettingsKeys.conversationProviderID)
        defaults.set("https://original.example/v1", forKey: AISettingsKeys.baseURL)
        defaults.set("explanation-model", forKey: AISettingsKeys.model)
        defaults.set("original-key", forKey: AISettingsKeys.apiKey)
        defaults.set("https://chat.example/v1", forKey: AISettingsKeys.conversationBaseURLKey(for: "anthropic"))
        defaults.set("chat-key", forKey: AISettingsKeys.conversationAPIKeyKey(for: "anthropic"))
        defaults.set("chat-model", forKey: AISettingsKeys.conversationModelKey(for: "anthropic"))

        let conversation = try AIConfiguration.current(profile: .conversation, defaults: defaults)
        let explanation = try AIConfiguration.current(defaults: defaults)
        #expect(conversation.baseURL == explanation.baseURL)
        #expect(conversation.baseURL.absoluteString == "https://original.example/v1")
        #expect(conversation.apiKey == "original-key")
        #expect(explanation.apiKey == "original-key")
        #expect(conversation.model == "chat-model")
        #expect(explanation.model == "explanation-model")
    }

    @Test
    func reasoningEffortIsIndependentPerProviderAndUsage() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults
        defaults.set("codex-cli", forKey: AISettingsKeys.providerID)
        defaults.set("codex-cli", forKey: AISettingsKeys.conversationProviderID)
        #expect(try AIConfiguration.current(defaults: defaults).reasoningEffort == "medium")
        #expect(try AIConfiguration.current(profile: .conversation, defaults: defaults).reasoningEffort == "high")

        defaults.set(" ultra \n", forKey: AIConfigurationProfile.explanation.reasoningEffortKey(for: "codex-cli"))
        defaults.set("low", forKey: AIConfigurationProfile.conversation.reasoningEffortKey(for: "codex-cli"))
        defaults.set("high", forKey: AIConfigurationProfile.explanation.reasoningEffortKey(for: "custom"))
        #expect(try AIConfiguration.current(defaults: defaults).reasoningEffort == "ultra")
        #expect(try AIConfiguration.current(profile: .conversation, defaults: defaults).reasoningEffort == "low")

        defaults.set(" \n", forKey: AIConfigurationProfile.explanation.reasoningEffortKey(for: "codex-cli"))
        #expect(try AIConfiguration.current(defaults: defaults).reasoningEffort == "medium")
        #expect(defaults.string(forKey: AIConfigurationProfile.explanation.reasoningEffortKey(for: "custom")) == "high")
    }

    @Test(arguments: ["", " \n "])
    func blankCodexDepthUsesApplicationDefaultForEachUsage(value: String) throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults
        for profile in AIConfigurationProfile.allCases {
            defaults.set("codex-cli", forKey: profile.providerIDKey)
            defaults.set(value, forKey: profile.reasoningEffortKey(for: "codex-cli"))
            let configuration = try AIConfiguration.current(profile: profile, defaults: defaults)
            #expect(configuration.reasoningEffort == profile.defaultCodexReasoningEffort)
            #expect(defaults.string(forKey: profile.reasoningEffortKey(for: "codex-cli")) == value)
        }
    }

    @Test
    func HTTPProvidersKeepUnspecifiedReasoningDepth() throws {
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let defaults = preferences.defaults
        defaults.set("key", forKey: AISettingsKeys.apiKeyKey(for: "openai"))
        for profile in AIConfigurationProfile.allCases {
            defaults.set("openai", forKey: profile.providerIDKey)
            #expect(try AIConfiguration.current(profile: profile, defaults: defaults).reasoningEffort == nil)
        }
    }

}
