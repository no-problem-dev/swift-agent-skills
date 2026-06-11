import Foundation
import StructuredDataCore
import YAMLParsing

/// Authoring side of `SKILL.md` — the inverse of ``SkillFrontmatter`` parsing.
///
/// Serializes ``SkillProperties`` to a standard-conformant frontmatter mapping
/// and full `SKILL.md` document. Pure (no filesystem), so it is CLI-testable and
/// round-trips with the parser: `parseFrontmatter(serialize(p, body))` recovers
/// `p` and `body`. Disk writing lives in `AgentSkillsDiscovery`'s `SkillWriter`.
public enum SkillDocument {

    private static let serializer = YAMLSerializer(options: .init(sortKeys: false))

    /// Builds the frontmatter mapping in canonical spec order, omitting absent
    /// optional fields. `metadata` keys are sorted for deterministic output.
    public static func frontmatter(_ properties: SkillProperties) -> OrderedObject {
        var object = OrderedObject()
        object.append(key: "name", value: .string(properties.name))
        object.append(key: "description", value: .string(properties.description))
        if let license = properties.license {
            object.append(key: "license", value: .string(license))
        }
        if let compatibility = properties.compatibility {
            object.append(key: "compatibility", value: .string(compatibility))
        }
        if let allowedTools = properties.allowedTools {
            object.append(key: "allowed-tools", value: .string(allowedTools))
        }
        if !properties.metadata.isEmpty {
            var metadata = OrderedObject()
            for key in properties.metadata.keys.sorted() {
                metadata.append(key: key, value: .string(properties.metadata[key]!))
            }
            object.append(key: "metadata", value: .object(metadata))
        }
        return object
    }

    /// Serializes the frontmatter mapping to YAML text (no `---` fences).
    public static func frontmatterYAML(_ properties: SkillProperties) -> String {
        serializer.string(from: .object(frontmatter(properties)))
    }

    /// Serializes a complete `SKILL.md` document: fenced frontmatter followed by
    /// the markdown body.
    public static func serialize(properties: SkillProperties, body: String) -> String {
        let yaml = frontmatterYAML(properties)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.isEmpty {
            return "---\n" + yaml + "---\n"
        }
        return "---\n" + yaml + "---\n\n" + trimmedBody + "\n"
    }

    /// Strict validation gate for authoring: the new artifact must fully conform
    /// (same rules as `skills-ref validate`). Returns error strings; empty = valid.
    public static func validate(_ properties: SkillProperties) -> [String] {
        SkillValidator.validate(frontmatter: frontmatter(properties), directoryName: properties.name)
    }
}
