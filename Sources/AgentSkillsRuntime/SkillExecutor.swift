import Foundation
import AgentSkillsDiscovery

/// Decides what happens to a skill's rendered content once it has been activated.
///
/// The built-in path is inline: the content goes into the current conversation. Running a skill
/// in a sub-agent — "fork" — is a client-specific pattern outside the standard, so it is left to
/// the consumer, which is what keeps this package independent of any agent runtime.
public protocol SkillExecutor: Sendable {
    /// Consumes an activated skill's rendered content.
    ///
    /// - Parameters:
    ///   - skill: The activated skill. `InvokeSkillTool` passes an identity-only value whose
    ///     name is set and whose body, description and resources are empty, so an executor that
    ///     needs the real skill must look it up itself.
    ///   - renderedContent: The wrapped body ``SkillActivator`` produced.
    /// - Returns: How the host should use the content.
    func run(_ skill: LoadedSkill, renderedContent: String) async throws -> SkillExecutionResult
}

/// What a host should do with an executed skill.
public enum SkillExecutionResult: Sendable, Equatable {
    /// Inject the content into the current conversation — the default path.
    case inline(content: String)
    /// A sub-agent ran the skill elsewhere and only this summary comes back.
    case forked(summary: String)
}

/// Hands the rendered content straight back for inline injection. The only executor this package
/// ships, and the one that matches the standard's built-in behavior.
public struct InlineSkillExecutor: SkillExecutor {
    public init() {}
    public func run(_ skill: LoadedSkill, renderedContent: String) async throws -> SkillExecutionResult {
        .inline(content: renderedContent)
    }
}
