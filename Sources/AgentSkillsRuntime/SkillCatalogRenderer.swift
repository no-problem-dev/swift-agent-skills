import Foundation
import AgentSkillsDiscovery

/// Renders the `<available_skills>` catalog for a system prompt from skills already in memory.
///
/// The production counterpart to the spec-shaped `AgentSkills.SkillCatalog`: it omits
/// `<location>` by default so the model cannot read a skill file itself and skip the activation
/// tool, which is how OpenHands behaves.
public struct SkillCatalogRenderer: Sendable {
    /// Emit `<location>`. Off by default: a path in the prompt is an invitation for the model to
    /// read the skill directly instead of calling the activation tool.
    public var includeLocation: Bool
    /// Descriptions longer than this are cut rather than rejected, so an over-long description
    /// reaches the model truncated mid-sentence.
    public var maxDescriptionLength: Int

    public init(includeLocation: Bool = false, maxDescriptionLength: Int = 1024) {
        self.includeLocation = includeLocation
        self.maxDescriptionLength = maxDescriptionLength
    }

    /// Renders the `<available_skills>` block.
    ///
    /// Skills are sorted by name and `& < >` are escaped in both name and description.
    ///
    /// - Parameter skills: Skills to advertise, usually a registry's policy-filtered list.
    /// - Returns: The block, or `nil` when `skills` is empty so a caller can drop the section
    ///   from the prompt instead of showing an empty one.
    public func render(_ skills: [LoadedSkill]) -> String? {
        guard !skills.isEmpty else { return nil }
        var lines = ["<available_skills>"]
        for skill in skills.sorted(by: { $0.name < $1.name }) {
            lines.append("  <skill>")
            lines.append("    <name>\(escape(skill.name))</name>")
            lines.append("    <description>\(escape(truncate(skill.description)))</description>")
            if includeLocation, case .file(let url) = skill.location {
                lines.append("    <location>\(escape(url.path))</location>")
            }
            lines.append("  </skill>")
        }
        lines.append("</available_skills>")
        return lines.joined(separator: "\n")
    }

    /// The paragraph that tells the model how to activate a skill. Put it before ``render(_:)``'s
    /// output; the catalog alone does not say what to do with the names.
    ///
    /// - Parameter toolName: Name of the registered activation tool, as the model must call it.
    public func instructions(toolName: String) -> String {
        """
        The following skills provide specialized instructions for specific tasks. \
        When a task matches a skill's description, call the \(toolName) tool with the \
        skill's name to load its full instructions.
        """
    }

    private func truncate(_ text: String) -> String {
        guard text.count > maxDescriptionLength else { return text }
        return String(text.prefix(maxDescriptionLength))
    }

    private func escape(_ string: String) -> String {
        var result = string.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        return result
    }
}
