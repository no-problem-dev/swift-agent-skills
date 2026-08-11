import Foundation
import PersistenceCore

/// Builds the `<available_skills>` block for an agent's system prompt, in the shape the standard
/// specifies.
///
/// This variant emits `<location>`, which hands the model a path it can read on its own and so
/// lets it skip the activation tool. Hosts that want the tool to be the only route should use
/// `SkillCatalogRenderer` in `AgentSkillsRuntime`, which omits the path by default.
public enum SkillCatalog {

    /// Renders the catalog block for the given skill directories.
    ///
    /// Reads every `SKILL.md` on the spot, and one broken skill fails the whole catalog. A host
    /// that already ran discovery should render from its loaded skills instead of re-reading.
    /// An empty input produces an empty `<available_skills>` block, not `nil`.
    ///
    /// - Parameters:
    ///   - skillDirectories: Directories that each contain a `SKILL.md`.
    ///   - fileSystem: Backend used to read the manifests.
    /// - Throws: ``SkillParseError`` or ``SkillValidationError`` from the first skill that fails
    ///   to read or parse.
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

    /// Escapes `& < > " '`, matching Python's `html.escape(quote: true)`.
    private static func htmlEscape(_ string: String) -> String {
        var result = string.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#x27;")
        return result
    }
}
