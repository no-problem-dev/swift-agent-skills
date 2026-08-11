import Foundation
import AgentSkills
import AgentSkillsDiscovery

/// What came of trying to activate a skill.
public enum SkillActivationOutcome: Sendable, Equatable {
    /// Rendered content, ready to inject. `alreadyActive` is `true` when this session activated
    /// the skill before, so a loop can skip re-injecting it — the content is returned either way.
    case activated(content: String, alreadyActive: Bool)
    /// No skill of that name is registered. Carries the policy-filtered names in sorted order,
    /// to hand back to the model.
    case unknown(available: [String])
    /// The skill exists but the policy hides it from the model; only the host can trigger it.
    case notModelInvocable(name: String)
}

/// Resolves a skill by name, renders its body and wraps it for injection into the conversation.
///
/// Independent of any LLM stack — it needs a registry, a body renderer and session state, and
/// the `Tool` adapter lives in `AgentSkillsTool`. Activation is recorded for de-duplication but
/// never blocked: activating the same skill twice returns the content again with
/// `alreadyActive` set, and it is the caller who decides to drop it.
public struct SkillActivator: Sendable {
    private let registry: SkillRegistry
    private let renderer: any SkillBodyRenderer
    private let session: SkillSessionState
    private let policy: SkillPolicy
    private let workingDirectory: URL?

    /// Creates an activator over a loaded registry.
    ///
    /// - Parameters:
    ///   - registry: Source of skills. Call its `load()` first, or every activation is unknown.
    ///   - renderer: Turns a skill body into injectable text. The default runs no commands.
    ///   - session: De-duplication state. Use one instance per conversation; a fresh one makes
    ///     every activation look like the first.
    ///   - policy: Decides which skills the model may activate. A hidden skill still resolves,
    ///     as ``SkillActivationOutcome/notModelInvocable(name:)``.
    ///   - workingDirectory: Handed to the renderer for resolving relative paths. `nil` lets the
    ///     renderer pick its own default.
    public init(
        registry: SkillRegistry,
        renderer: any SkillBodyRenderer = PlainSkillRenderer(),
        session: SkillSessionState = SkillSessionState(),
        policy: SkillPolicy = .init(),
        workingDirectory: URL? = nil
    ) {
        self.registry = registry
        self.renderer = renderer
        self.session = session
        self.policy = policy
        self.workingDirectory = workingDirectory
    }

    /// Resolves a name, renders that skill and records the activation.
    ///
    /// The name is trimmed before lookup, but matched exactly after that — there is no fuzzy
    /// resolution. A policy-hidden skill is reported as not model-invocable rather than unknown,
    /// so the model is not told to guess again.
    ///
    /// - Parameter rawName: Skill name as the model wrote it; surrounding whitespace is ignored.
    /// - Returns: The wrapped content, or the reason it could not be activated.
    /// - Throws: Whatever the renderer throws. ``PlainSkillRenderer`` never does.
    public func activate(name rawName: String) async throws -> SkillActivationOutcome {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let skill = await registry.get(name) else {
            let available = await registry.available(policy: policy).map(\.name)
            return .unknown(available: available)
        }
        guard policy.isAllowed(name) else {
            return .notModelInvocable(name: name)
        }

        let body = try await renderer.render(skill, workingDirectory: workingDirectory)
        let content = wrap(skill: skill, body: body)
        let isFirst = await session.record(name)
        return .activated(content: content, alreadyActive: !isFirst)
    }

    /// Wraps the rendered body in `<skill_content>`, appending the base-directory footer and the
    /// bundled file list (the OpenCode/OpenHands shape).
    private func wrap(skill: LoadedSkill, body: String) -> String {
        var lines = ["<skill_content name=\"\(skill.name)\">"]
        lines.append(body.trimmingCharacters(in: .whitespacesAndNewlines))

        if case .file(let manifest) = skill.location {
            let dir = manifest.deletingLastPathComponent().path
            lines.append("")
            lines.append("Base directory for this skill: \(dir)")
            lines.append("Relative paths (e.g. scripts/, references/, assets/) are relative to that directory.")
        }

        if let resources = skill.resources, resources.hasResources {
            lines.append("<skill_files>")
            for file in resources.scripts + resources.references + resources.assets {
                lines.append("<file>\(file)</file>")
            }
            lines.append("</skill_files>")
        }

        lines.append("</skill_content>")
        return lines.joined(separator: "\n")
    }
}
