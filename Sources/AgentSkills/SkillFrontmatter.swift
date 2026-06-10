import Foundation
import StructuredDataCore
import YAMLParsing
import PersistenceCore

/// YAML frontmatter parsing for `SKILL.md` files.
///
/// Ports `skills-ref` parser.py. Pure parsing (``parseFrontmatter(_:)``) needs
/// no filesystem; the directory-driven entry points take an injected
/// ``FileSystemReading`` so they are swappable and testable in-memory.
public enum SkillFrontmatter {

    private static let yaml = YAMLParser()

    /// Splits `SKILL.md` content into frontmatter mapping and markdown body.
    ///
    /// - Throws: ``SkillParseError`` if frontmatter is missing, unclosed, invalid
    ///   YAML, or not a mapping.
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

    /// Locates the skill manifest, preferring `SKILL.md` over `skill.md`.
    public static func findSkillMD(in skillDirectory: URL, fileSystem: some FileSystemReading) async -> URL? {
        for name in ["SKILL.md", "skill.md"] {
            let candidate = skillDirectory.appendingPathComponent(name)
            if await fileSystem.exists(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Reads parsed properties from a skill directory's `SKILL.md`.
    ///
    /// Does not perform full validation (use ``SkillValidator``).
    ///
    /// - Throws: ``SkillParseError`` if the manifest is missing or malformed,
    ///   ``SkillValidationError`` if `name`/`description` are missing.
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
