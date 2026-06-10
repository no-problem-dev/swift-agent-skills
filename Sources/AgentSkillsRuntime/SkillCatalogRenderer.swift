import Foundation
import AgentSkillsDiscovery

/// Renders the Tier-1 `<available_skills>` catalog for the system prompt.
///
/// Production variant (distinct from the spec-parity `AgentSkills.SkillCatalog`):
/// by default it **omits `<location>`** so the model cannot bypass the
/// activation tool by reading the file directly (OpenHands behavior).
public struct SkillCatalogRenderer: Sendable {
    public var includeLocation: Bool
    public var maxDescriptionLength: Int

    public init(includeLocation: Bool = false, maxDescriptionLength: Int = 1024) {
        self.includeLocation = includeLocation
        self.maxDescriptionLength = maxDescriptionLength
    }

    /// The `<available_skills>` block, or `nil` when there are no skills (so the
    /// loop can omit the section entirely rather than show an empty one).
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

    /// Short instruction block telling the model how to activate skills.
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
