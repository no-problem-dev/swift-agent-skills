import Foundation
import LLMClient
import LLMTool
import AgentSkillsDiscovery
import AgentSkillsRuntime

/// The `invoke_skill` tool the agent loop registers — a first-class `Tool` so it
/// can carry the Tier-1 `<available_skills>` catalog in its `systemInstruction`.
///
/// This unifies, by construction, the two things OpenHands derives separately
/// from `agent_context.skills` (catalog → system message; auto-attached tool):
/// here one snapshot of `[LoadedSkill]` produces BOTH the catalog (the loop
/// injects it via `Tool.systemInstruction`, exactly like SendA2UIToClientTool)
/// AND the `name` enum the model must pick from. The model can never see a skill
/// it cannot invoke, and vice versa.
public struct InvokeSkillTool: Tool {

    public static let toolName = "invoke_skill"

    private let availableNames: [String]
    private let activator: SkillActivator
    private let executor: any SkillExecutor
    private let catalog: String?

    public var toolName: String { Self.toolName }

    public var toolDescription: String {
        """
        Invoke a skill by name to load its full instructions. This is the only \
        supported way to activate a skill listed in <available_skills>. Call it \
        with the exact name shown there; the skill's full content is returned.
        """
    }

    public var inputSchema: JSONSchema {
        JSONSchema.object(fields: [
            JSONSchema.enum(
                availableNames,
                description: "The name of the skill from <available_skills>."
            ).named("name")
        ])
    }

    /// The catalog rides along into the system prompt automatically (the loop
    /// collects `Tool.systemInstruction`).
    public var systemInstruction: String? { catalog }

    public func execute(with argumentsData: Data) async throws -> ToolResult {
        let name: String
        if let decoded = try? JSONDecoder().decode(Input.self, from: argumentsData), !decoded.name.isEmpty {
            name = decoded.name
        } else {
            return .error("Missing required parameter 'name'.")
        }

        let outcome = try await activator.activate(name: name)
        switch outcome {
        case .activated(let content, _):
            switch try await executor.run(Self.identity(name), renderedContent: content) {
            case .inline(let text): return .text(text)
            case .forked(let summary): return .text(summary)
            }
        case .unknown(let available):
            return .error("Unknown skill '\(name)'. Available skills: \(available.joined(separator: ", ")).")
        case .notModelInvocable(let blocked):
            return .error("Skill '\(blocked)' cannot be invoked directly; it is trigger-only.")
        }
    }

    private struct Input: Decodable { let name: String }

    // MARK: - Construction

    /// Builds the tool from one snapshot of available skills — the single source
    /// for both the catalog and the `name` enum. Returns `nil` when there are no
    /// skills (don't register an empty tool / empty catalog).
    public static func make(
        skills: [LoadedSkill],
        activator: SkillActivator,
        catalogRenderer: SkillCatalogRenderer = SkillCatalogRenderer(),
        executor: any SkillExecutor = InlineSkillExecutor()
    ) -> InvokeSkillTool? {
        guard !skills.isEmpty else { return nil }
        let names = skills.map(\.name).sorted()
        let catalog = catalogRenderer.render(skills).map {
            catalogRenderer.instructions(toolName: toolName) + "\n" + $0
        }
        return InvokeSkillTool(availableNames: names, activator: activator, executor: executor, catalog: catalog)
    }

    /// The inline executor only needs a skill's identity; avoid a second registry
    /// lookup in the tool layer.
    private static func identity(_ name: String) -> LoadedSkill {
        LoadedSkill(
            name: name, description: "", body: "",
            location: .builtin(name: name),
            properties: .init(name: name, description: "")
        )
    }
}
