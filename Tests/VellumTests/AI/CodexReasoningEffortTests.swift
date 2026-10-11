import Foundation
import Testing
@testable import VellumCore

@Suite("Codex reasoning effort")
struct CodexReasoningEffortTests {
    @Test(arguments: [nil, "ultra"] as [String?])
    func forwardsExplicitEffortAndPreservesLowLevelOmission(effort: String?) async throws {
        let server = try fakeServer(reasoningEffort: effort)
        defer { try? FileManager.default.removeItem(at: server.directory) }
        _ = try await CodexAppServerAIExplanationClient().testFunction(configuration: server.configuration)
        let requests = try recordedRequests(in: server.directory)
        let thread = try #require(requests.first { $0["method"] as? String == "thread/start" }?["params"] as? [String: Any])
        let turn = try #require(requests.first { $0["method"] as? String == "turn/start" }?["params"] as? [String: Any])
        #expect((thread["config"] as? [String: Any])?["model_reasoning_effort"] as? String == effort)
        #expect(turn["effort"] as? String == effort)
        #expect(thread["model"] as? String == "gpt-test")
        #expect(turn["model"] as? String == "gpt-test")
        if effort == nil { #expect(thread["config"] == nil) }
    }

    @Test(arguments: AIConfigurationProfile.allCases)
    func applicationProfileDefaultsReachActualFunctionRequests(profile: AIConfigurationProfile) async throws {
        let server = try fakeServer()
        defer { try? FileManager.default.removeItem(at: server.directory) }
        let suiteName = "VellumTests.CodexDepth.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("codex-cli", forKey: profile.providerIDKey)
        defaults.set(server.configuration.codexExecutablePath, forKey: profile.baseURLKey(for: "codex-cli"))
        defaults.set("gpt-test", forKey: profile.modelKey(for: "codex-cli"))
        let configuration = try AIConfiguration.current(profile: profile, defaults: defaults)

        _ = try await CodexAppServerAIExplanationClient().testFunction(configuration: configuration)
        let requests = try recordedRequests(in: server.directory)
        let thread = try #require(requests.first { $0["method"] as? String == "thread/start" }?["params"] as? [String: Any])
        let turn = try #require(requests.first { $0["method"] as? String == "turn/start" }?["params"] as? [String: Any])
        #expect((thread["config"] as? [String: Any])?["model_reasoning_effort"] as? String == profile.defaultCodexReasoningEffort)
        #expect(turn["effort"] as? String == profile.defaultCodexReasoningEffort)
    }

    @Test
    func readsAllModelCatalogPagesWithoutReadingLocalConfiguration() async throws {
        let server = try fakeServer()
        defer { try? FileManager.default.removeItem(at: server.directory) }
        let settings = try await CodexAppServerAIExplanationClient().fetchSettings(configuration: server.configuration)
        #expect(settings.models.map(\.id) == ["gpt-test", "gpt-other"])
        #expect(settings.model(for: server.configuration)?.supportedReasoningEfforts == ["low", "ultra"])
        let requests = try recordedRequests(in: server.directory)
        #expect(!requests.contains { $0["method"] as? String == "config/read" })
        let pages = requests.filter { $0["method"] as? String == "model/list" }
        #expect(pages.count == 2)
        #expect((pages.last?["params"] as? [String: Any])?["cursor"] as? String == "next")
    }

    @Test
    func findsCapabilitiesOnlyForExplicitKnownModels() throws {
        let model = CodexModelInfo(id: "gpt-test", supportedReasoningEfforts: ["low", "high", "ultra"])
        let settings = CodexSettingsSnapshot(models: [model])
        let blankModel = try configuration(model: "", reasoningEffort: "high")
        let explicit = try configuration(model: "gpt-test", reasoningEffort: "low")
        #expect(settings.model(for: blankModel) == nil)
        #expect(settings.model(for: explicit) == model)
        let unknown = try configuration(model: "custom-model")
        #expect(settings.model(for: unknown) == nil)
    }

    private func configuration(model: String, reasoningEffort: String? = nil) throws -> AIConfiguration {
        try AIConfiguration(baseURLString: "/synthetic/codex", model: model, apiKey: "", providerFormat: .codexCLI, reasoningEffort: reasoningEffort)
    }

    private func recordedRequests(in directory: URL) throws -> [[String: Any]] {
        try String(contentsOf: directory.appendingPathComponent("requests"), encoding: .utf8)
            .split(separator: "\n")
            .compactMap { CodexAppServerMessageParser.message(from: String($0)) }
    }

    private func fakeServer(reasoningEffort: String? = nil) throws -> (directory: URL, configuration: AIConfiguration) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fake-codex")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          printf '%s\\n' "$line" >> '\(directory.path)/requests'
          case "$line" in
            *'"method":"initialize"'*)
              printf '%s\\n' '{"id":0,"result":{}}' ;;
            *'"method":"config'*'read"'*)
              printf '%s\\n' '{"id":1,"error":{"message":"Local configuration must not be read"}}' ;;
            *'"method":"model'*'list"'*)
              case "$line" in
                *'"cursor":"next"'*)
                  printf '%s\\n' '{"id":1,"result":{"data":[{"id":"gpt-other","defaultReasoningEffort":"medium","supportedReasoningEfforts":[]}],"nextCursor":null}}' ;;
                *)
                  printf '%s\\n' '{"id":1,"result":{"data":[{"id":"catalog-id","model":"gpt-test","defaultReasoningEffort":"low","isDefault":true,"supportedReasoningEfforts":[{"reasoningEffort":"low"},{"reasoningEffort":"ultra"}]}],"nextCursor":"next"}}' ;;
              esac ;;
            *'"method":"thread'*'start"'*)
              printf '%s\\n' '{"id":1,"result":{"thread":{"id":"thread"}}}' ;;
            *'"method":"turn'*'start"'*)
              printf '%s\\n' '{"id":2,"result":{"turn":{"id":"turn"}}}'
              printf '%s\\n' '{"method":"item/completed","params":{"threadId":"thread","turnId":"turn","item":{"type":"agentMessage","text":"OK"}}}'
              printf '%s\\n' '{"method":"turn/completed","params":{"threadId":"thread","turn":{"id":"turn","status":"completed"}}}' ;;
          esac
        done
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return (directory, try AIConfiguration(baseURLString: executable.path, model: "gpt-test", apiKey: "", providerFormat: .codexCLI, reasoningEffort: reasoningEffort))
    }
}
