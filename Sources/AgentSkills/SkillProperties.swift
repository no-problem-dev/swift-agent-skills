import Foundation
import StructuredDataCore

/// Properties parsed from a skill's `SKILL.md` frontmatter.
///
/// Mirrors `skills-ref` `SkillProperties` (models.py). The standard surface is
/// exactly these six fields — `name` and `description` required, the rest
/// optional. Any other frontmatter field is a validation error.
public struct SkillProperties: Sendable, Equatable, Codable {
    /// Skill name in kebab-case (required).
    public var name: String
    /// What the skill does and when to use it (required).
    public var description: String
    /// License for the skill (optional).
    public var license: String?
    /// Environment/compatibility notes (optional).
    public var compatibility: String?
    /// Space-delimited pre-approved tool patterns (optional, experimental).
    public var allowedTools: String?
    /// Client-specific key/value metadata (defaults to empty).
    public var metadata: [String: String]

    public init(
        name: String,
        description: String,
        license: String? = nil,
        compatibility: String? = nil,
        allowedTools: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.name = name
        self.description = description
        self.license = license
        self.compatibility = compatibility
        self.allowedTools = allowedTools
        self.metadata = metadata
    }

    /// Builds properties from already-parsed frontmatter.
    ///
    /// Performs only the required-field checks that `skills-ref` `read_properties`
    /// does; full validation is ``SkillValidator``.
    ///
    /// - Throws: ``SkillValidationError`` if `name`/`description` are missing or
    ///   not non-empty strings.
    public init(frontmatter: OrderedObject) throws {
        guard frontmatter["name"] != nil else {
            throw SkillValidationError("Missing required field in frontmatter: name")
        }
        guard frontmatter["description"] != nil else {
            throw SkillValidationError("Missing required field in frontmatter: description")
        }
        guard let name = frontmatter["name"]?.string, !name.trimmed.isEmpty else {
            throw SkillValidationError("Field 'name' must be a non-empty string")
        }
        guard let description = frontmatter["description"]?.string, !description.trimmed.isEmpty else {
            throw SkillValidationError("Field 'description' must be a non-empty string")
        }

        self.name = name.trimmed
        self.description = description.trimmed
        self.license = frontmatter["license"]?.string
        self.compatibility = frontmatter["compatibility"]?.string
        self.allowedTools = frontmatter["allowed-tools"]?.string
        self.metadata = Self.stringifiedMetadata(frontmatter["metadata"])
    }

    /// Coerces a `metadata` mapping's values to strings, matching the reference
    /// `{str(k): str(v)}`. Numbers keep their verbatim source text.
    public static func stringifiedMetadata(_ value: StructuredValue?) -> [String: String] {
        guard let object = value?.object else { return [:] }
        var result: [String: String] = [:]
        for key in object.keys {
            if let scalar = object[key].map(stringifyScalar) {
                result[key] = scalar
            }
        }
        return result
    }

    static func stringifyScalar(_ value: StructuredValue) -> String {
        if let string = value.string { return string }
        if let number = value.numberValue { return number.text }
        if let bool = value.bool { return bool ? "true" : "false" }
        return ""
    }
}

extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
