import Foundation
import AgentSkillsDiscovery

/// Turns a skill body into the text that gets injected, immediately before injection.
///
/// The default, ``PlainSkillRenderer``, returns the body unchanged. A renderer that executes
/// inline `` !`cmd` `` blocks is the largest attack surface in this whole flow, because skill
/// content is untrusted input — so this package ships no such implementation and never makes one
/// the default. A host that wants it has to write and opt into it.
public protocol SkillBodyRenderer: Sendable {
    /// Renders a skill body for injection.
    ///
    /// - Parameters:
    ///   - skill: The skill being activated.
    ///   - workingDirectory: Directory a dynamic renderer resolves relative paths against.
    ///     Renderers that do not need it ignore it.
    /// - Returns: Text to inject into the conversation.
    /// - Throws: Whatever the rendering step can fail with. ``PlainSkillRenderer`` never throws.
    func render(_ skill: LoadedSkill, workingDirectory: URL?) async throws -> String
}

/// Returns the skill body unchanged. The secure default: it executes nothing.
public struct PlainSkillRenderer: SkillBodyRenderer {
    public init() {}
    public func render(_ skill: LoadedSkill, workingDirectory: URL?) async throws -> String {
        skill.body
    }
}
