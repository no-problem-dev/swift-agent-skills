import Foundation
import AgentSkillsDiscovery

/// How a skill is run once activated.
///
/// The standard, built-in path is **inline**: the rendered body is injected into
/// the current conversation. Running a skill in a separate subagent session
/// ("fork") is an OPTIONAL pattern only some clients support and is NOT part of
/// the Agent Skills standard — so it is modeled as an injected implementation a
/// consumer provides, keeping this package free of any agent-runtime dependency.
public protocol SkillExecutor: Sendable {
    func run(_ skill: LoadedSkill, renderedContent: String) async throws -> SkillExecutionResult
}

/// Result of running a skill.
public enum SkillExecutionResult: Sendable, Equatable {
    /// Inject the content into the current conversation (the default path).
    case inline(content: String)
    /// A subagent ran the skill and produced this summary (consumer-provided).
    case forked(summary: String)
}

/// Built-in inline executor: returns the rendered content for in-conversation
/// injection. The only executor this package ships.
public struct InlineSkillExecutor: SkillExecutor {
    public init() {}
    public func run(_ skill: LoadedSkill, renderedContent: String) async throws -> SkillExecutionResult {
        .inline(content: renderedContent)
    }
}
