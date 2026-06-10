import Foundation
import LLMClient
import LLMTool
import AgentSkillsDiscovery
import AgentSkillsRuntime

/// Builds the `invoke_skill` `Tool` that the agent loop registers.
///
/// This is the only LLM-coupled surface of the package. It wraps the pure
/// ``SkillActivator`` in a `DynamicTool` whose `name` parameter is constrained to
/// the set of currently-available skill names (an enum) so the model cannot
/// hallucinate a skill — per the official client-implementation guide.
public enum InvokeSkillTool {

    public static let toolName = "invoke_skill"

    private static let description = """
    Invoke a skill by name to load its full instructions. This is the only \
    supported way to activate a skill listed in <available_skills>. Call it with \
    the exact name shown there; the skill's full content is returned as the result.
    """

    /// Creates the tool from a snapshot of available skill names plus an activator.
    ///
    /// Rebuild this per session/turn so the `name` enum reflects the live catalog.
    /// Returns `nil` when no skills are available (don't register an empty tool).
    public static func make(
        availableNames: [String],
        activator: SkillActivator,
        executor: any SkillExecutor = InlineSkillExecutor()
    ) -> DynamicTool? {
        guard !availableNames.isEmpty else { return nil }

        let schema = JSONSchema.object(fields: [
            JSONSchema.enum(
                availableNames.sorted(),
                description: "The name of the skill from <available_skills>."
            ).named("name")
        ])

        return DynamicTool(
            name: toolName,
            description: description,
            inputSchema: schema
        ) { (args: ToolArguments) in
            guard let name = args.string("name") else {
                return .error("Missing required parameter 'name'.")
            }
            let outcome = try await activator.activate(name: name)
            switch outcome {
            case .activated(let content, _):
                let result = try await executor.run(
                    placeholderSkill(name: name), renderedContent: content
                )
                switch result {
                case .inline(let text): return .text(text)
                case .forked(let summary): return .text(summary)
                }
            case .unknown(let available):
                return .error("Unknown skill '\(name)'. Available skills: \(available.joined(separator: ", ")).")
            case .notModelInvocable(let blocked):
                return .error("Skill '\(blocked)' cannot be invoked directly; it is trigger-only.")
            }
        }
    }

    /// The executor only needs identity for inline activation; a lightweight stand-in
    /// avoids a second registry lookup in the tool layer.
    private static func placeholderSkill(name: String) -> LoadedSkill {
        LoadedSkill(
            name: name, description: "", body: "",
            location: .builtin(name: name),
            properties: .init(name: name, description: "")
        )
    }
}
