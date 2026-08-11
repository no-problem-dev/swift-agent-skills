import Foundation
import LLMClient
import LLMTool
import AgentSkillsDiscovery
import AgentSkillsRuntime

/// The `invoke_skill` tool an agent loop registers so the model can load a skill's full
/// instructions.
///
/// One snapshot of `[LoadedSkill]` produces both halves of the contract: the `<available_skills>`
/// catalog, carried in ``systemInstruction`` for the loop to inject, and the `name` enum in
/// ``inputSchema``. The model can therefore never be shown a skill it cannot call, or call one it
/// was not shown.
///
/// The snapshot is frozen at construction. Reloading the registry does not update this tool —
/// build a new one with ``make(skills:activator:catalogRenderer:executor:)``.
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

    /// The activation instructions and catalog, which the loop injects into the system prompt.
    /// Do not also render the catalog yourself, or the model sees it twice.
    public var systemInstruction: String? { catalog }

    /// Activates the skill named in the arguments and returns its content to the model.
    ///
    /// Bad input never throws: missing or empty `name`, an unknown skill and a trigger-only skill
    /// all come back as `ToolResult.error` text the model can read and correct itself against.
    ///
    /// - Parameter argumentsData: JSON tool arguments. Only `name` is read; anything else is
    ///   ignored.
    /// - Returns: The wrapped skill content, or an error result — the unknown-skill one lists
    ///   the names that would have worked.
    /// - Throws: Whatever the activator's renderer or the executor throws.
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

    /// Builds the tool from a snapshot of available skills, the single source for both the
    /// catalog and the `name` enum.
    ///
    /// - Parameters:
    ///   - skills: Skills to advertise, typically a registry's `available()` list.
    ///   - activator: Resolves and renders a skill when the model calls the tool. It must be
    ///     backed by the same registry these skills came from, or advertised names will not
    ///     resolve.
    ///   - catalogRenderer: Renders the catalog block. The default hides skill file paths.
    ///   - executor: What to do with the rendered content. The default injects it inline.
    /// - Returns: `nil` when `skills` is empty, so a host can skip registering a tool whose
    ///   `name` enum would have no cases.
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

    /// Name-only skill handed to the executor, avoiding a second registry lookup. Body,
    /// description and resources are empty, so a custom executor cannot read them.
    private static func identity(_ name: String) -> LoadedSkill {
        LoadedSkill(
            name: name, description: "", body: "",
            location: .builtin(name: name),
            properties: .init(name: name, description: "")
        )
    }
}
