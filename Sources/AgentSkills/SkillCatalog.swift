import Foundation
import PersistenceCore

/// Generates the `<available_skills>` XML block for agent system prompts.
///
/// Ports `skills-ref` prompt.py for byte-level parity. This is the reference
/// catalog form (it **includes** `<location>`); the runtime layer may choose a
/// location-hidden variant to force tool-based activation.
public enum SkillCatalog {

    /// Builds the catalog block for the given skill directories.
    ///
    /// - Throws: ``SkillParseError`` / ``SkillValidationError`` if any skill's
    ///   `SKILL.md` cannot be read.
    public static func toPrompt(
        skillDirectories: [URL],
        fileSystem: some FileSystemReading
    ) async throws -> String {
        if skillDirectories.isEmpty {
            return "<available_skills>\n</available_skills>"
        }

        var lines = ["<available_skills>"]
        for directory in skillDirectories {
            let resolved = directory.standardizedFileURL
            let props = try await SkillFrontmatter.readProperties(from: resolved, fileSystem: fileSystem)

            lines.append("<skill>")
            lines.append("<name>")
            lines.append(htmlEscape(props.name))
            lines.append("</name>")
            lines.append("<description>")
            lines.append(htmlEscape(props.description))
            lines.append("</description>")

            let manifest = await SkillFrontmatter.findSkillMD(in: resolved, fileSystem: fileSystem)
            lines.append("<location>")
            lines.append(manifest?.path ?? "")
            lines.append("</location>")

            lines.append("</skill>")
        }
        lines.append("</available_skills>")
        return lines.joined(separator: "\n")
    }

    /// Mirrors Python `html.escape(quote=True)`: escapes `& < > " '`.
    private static func htmlEscape(_ string: String) -> String {
        var result = string.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#x27;")
        return result
    }
}
