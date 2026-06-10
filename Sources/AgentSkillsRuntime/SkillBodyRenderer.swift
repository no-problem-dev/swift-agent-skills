import Foundation
import AgentSkillsDiscovery

/// Renders a skill's body just before it enters context.
///
/// The default ``PlainSkillRenderer`` returns the body unchanged. Dynamic
/// rendering that executes inline `` !`cmd` `` blocks is a SEPARATE, opt-in
/// implementation: executing shell from skill content is the single highest-risk
/// surface, so it is never the default.
public protocol SkillBodyRenderer: Sendable {
    func render(_ skill: LoadedSkill, workingDirectory: URL?) async throws -> String
}

/// Identity renderer — no command execution. The secure default.
public struct PlainSkillRenderer: SkillBodyRenderer {
    public init() {}
    public func render(_ skill: LoadedSkill, workingDirectory: URL?) async throws -> String {
        skill.body
    }
}
