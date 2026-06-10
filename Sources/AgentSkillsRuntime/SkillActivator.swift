import Foundation
import AgentSkills
import AgentSkillsDiscovery

/// Outcome of attempting to activate a skill by name.
public enum SkillActivationOutcome: Sendable, Equatable {
    /// Rendered skill content ready to inject; `alreadyActive` is true on a
    /// repeat activation (the loop may skip re-injection).
    case activated(content: String, alreadyActive: Bool)
    /// No such advertised skill; carries the sorted available names for the model.
    case unknown(available: [String])
    /// The skill exists but is not model-invocable (trigger-only).
    case notModelInvocable(name: String)
}

/// Tier-2 activation: resolves a skill name, renders its body, wraps it for the
/// conversation, and records the invocation for dedupe.
///
/// Pure with respect to any LLM stack — it only needs the registry, a body
/// renderer, and session state. The `Tool` adapter lives in `AgentSkillsTool`.
public struct SkillActivator: Sendable {
    private let registry: SkillRegistry
    private let renderer: any SkillBodyRenderer
    private let session: SkillSessionState
    private let policy: SkillPolicy
    private let workingDirectory: URL?

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

    /// Wraps the rendered body in `<skill_content>` with a base-directory footer
    /// and a (non-eager) resource file listing — the OpenCode/OpenHands shape.
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
