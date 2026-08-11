import Foundation
import StructuredDataCore
import YAMLParsing

/// Turns skill properties back into `SKILL.md` text — the authoring side of frontmatter parsing.
///
/// Pure: nothing here touches a filesystem, so it is safe to call from anywhere. Writing the
/// result to disk is `SkillWriter`'s job, in `AgentSkillsDiscovery`.
///
/// `SkillFrontmatter.parseFrontmatter(serialize(p, body))` gives back `p` and the trimmed body,
/// but only for values that survive the fence scan: a field whose value contains `---` closes
/// the frontmatter early when it is read back.
public enum SkillDocument {

    private static let serializer = YAMLSerializer(options: .init(sortKeys: false))

    /// Builds the frontmatter mapping in the field order the standard prescribes.
    ///
    /// Unset optional fields are omitted, and `metadata` keys are sorted, so the same properties
    /// always produce the same bytes.
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

    /// Serializes the frontmatter mapping to YAML text, without the surrounding `---` fences.
    public static func frontmatterYAML(_ properties: SkillProperties) -> String {
        serializer.string(from: .object(frontmatter(properties)))
    }

    /// Serializes a complete `SKILL.md`: fenced frontmatter followed by the markdown body.
    ///
    /// The body is trimmed; an empty one yields a frontmatter-only document.
    ///
    /// - Parameters:
    ///   - properties: Frontmatter fields to emit.
    ///   - body: Markdown instructions to place after the closing fence.
    public static func serialize(properties: SkillProperties, body: String) -> String {
        let yaml = frontmatterYAML(properties)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.isEmpty {
            return "---\n" + yaml + "---\n"
        }
        return "---\n" + yaml + "---\n\n" + trimmedBody + "\n"
    }

    /// Runs the strict gate an author should pass before writing a skill to disk.
    ///
    /// The directory-name check uses `properties.name` as the directory, so that one rule can
    /// never fail here — validate the real directory with ``SkillValidator`` if it matters.
    ///
    /// - Returns: One message per problem; empty means the properties are publishable.
    public static func validate(_ properties: SkillProperties) -> [String] {
        SkillValidator.validate(frontmatter: frontmatter(properties), directoryName: properties.name)
    }
}
