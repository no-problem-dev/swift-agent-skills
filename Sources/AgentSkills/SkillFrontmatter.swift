import Foundation
import StructuredDataCore
import YAMLParsing
import PersistenceCore

/// Splits `SKILL.md` text into YAML frontmatter and markdown body.
///
/// Strict: anything malformed throws. Discovery wants the opposite and loads a broken skill
/// anyway — see `FileSystemSkillDiscovery` in `AgentSkillsDiscovery`.
///
/// ``parseFrontmatter(_:)`` is pure; the directory-based entry points take a `FileSystemReading`
/// so they can run against an in-memory tree in tests.
public enum SkillFrontmatter {

    private static let yaml = YAMLParser()

    /// Splits `SKILL.md` content into its frontmatter mapping and the trimmed markdown body.
    ///
    /// The closing fence is the next `---` anywhere in the text, quoting included, so a value
    /// containing `---` ends the block early and the remainder fails to parse as YAML.
    ///
    /// - Parameter content: Full text of a `SKILL.md` file.
    /// - Returns: The frontmatter mapping and the body with surrounding whitespace removed.
    /// - Throws: ``SkillParseError`` when the frontmatter is missing, unterminated, invalid YAML,
    ///   or not a mapping.
    public static func parseFrontmatter(_ content: String) throws -> (frontmatter: OrderedObject, body: String) {
        guard content.hasPrefix("---") else {
            throw SkillParseError.mustStartWithFrontmatter
        }

        // Equivalent to Python `content.split("---", 2)`: text between the first
        // and second `---`, then everything after the second.
        let afterFirst = content.dropFirst(3)
        guard let separator = afterFirst.range(of: "---") else {
            throw SkillParseError.notProperlyClosed
        }
        let frontmatterText = String(afterFirst[afterFirst.startIndex..<separator.lowerBound])
        let body = String(afterFirst[separator.upperBound...]).trimmed

        let parsed: StructuredValue
        do {
            parsed = try yaml.parse(frontmatterText)
        } catch {
            throw SkillParseError.invalidYAML(String(describing: error))
        }

        guard let mapping = parsed.object else {
            throw SkillParseError.notAMapping
        }
        return (mapping, body)
    }

    /// Locates a skill's manifest, preferring `SKILL.md` over `skill.md`.
    ///
    /// Only those two names are tried, and only directly inside the directory. Returns `nil`
    /// rather than throwing when neither exists.
    ///
    /// - Parameters:
    ///   - skillDirectory: Directory expected to hold the manifest.
    ///   - fileSystem: Backend used for the existence checks.
    public static func findSkillMD(in skillDirectory: URL, fileSystem: some FileSystemReading) async -> URL? {
        for name in ["SKILL.md", "skill.md"] {
            let candidate = skillDirectory.appendingPathComponent(name)
            if await fileSystem.exists(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Reads a skill directory's `SKILL.md` and parses its frontmatter into properties.
    ///
    /// Checks only that `name` and `description` are present and non-empty. Naming, length and
    /// unknown-field rules are not applied — use ``SkillValidator`` for those.
    ///
    /// - Parameters:
    ///   - skillDirectory: Directory containing `SKILL.md` (or `skill.md`).
    ///   - fileSystem: Backend used to find and read the manifest.
    /// - Throws: ``SkillParseError`` when the manifest is missing or malformed, or
    ///   ``SkillValidationError`` when `name` or `description` is missing or blank.
    public static func readProperties(
        from skillDirectory: URL,
        fileSystem: some FileSystemReading
    ) async throws -> SkillProperties {
        guard let manifest = await findSkillMD(in: skillDirectory, fileSystem: fileSystem) else {
            throw SkillParseError.skillMDNotFound(in: skillDirectory.path)
        }
        let content = try await fileSystem.readString(manifest)
        let (frontmatter, _) = try parseFrontmatter(content)
        return try SkillProperties(frontmatter: frontmatter)
    }
}
