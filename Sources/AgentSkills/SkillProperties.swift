import Foundation
import StructuredDataCore

/// The six frontmatter fields the Agent Skills standard defines for a skill.
///
/// `name` and `description` are required, the rest are optional, and any other key is a
/// validation error — so this type cannot carry unknown fields: they are dropped on parse and
/// never written back.
public struct SkillProperties: Sendable, Equatable, Codable {
    /// Skill identifier: lowercase letters, digits and single hyphens, and it must equal the
    /// name of the directory the skill lives in.
    public var name: String
    /// What the skill does and when to use it.
    ///
    /// The only text a model sees before deciding to activate the skill, and the field the
    /// catalog truncates at 1024 characters.
    public var description: String
    /// License of the skill's content. Nothing validates the value.
    public var license: String?
    /// Free-form note about what the skill needs in order to run. Capped at 500 characters;
    /// nothing in this package interprets it.
    public var compatibility: String?
    /// Space-separated tool patterns a host may pre-approve. Experimental, and never enforced
    /// here — a host that honors it has to do so itself.
    public var allowedTools: String?
    /// Client-specific key/value pairs. Values are coerced to strings when parsed, so
    /// `version: 1.0` reads back as `"1.0"`.
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

    /// Builds properties from an already-parsed frontmatter mapping.
    ///
    /// Enforces only the two required fields. Naming, length and unknown-field rules are not
    /// checked, so a value that initializes fine here can still fail ``SkillValidator``.
    /// `name` and `description` are trimmed; the optional fields are taken as written.
    ///
    /// - Parameter frontmatter: Mapping from ``SkillFrontmatter/parseFrontmatter(_:)``.
    /// - Throws: ``SkillValidationError`` when `name` or `description` is absent, not a string,
    ///   or blank.
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

    /// Coerces a `metadata` mapping's values to strings.
    ///
    /// Numbers keep their source text, so `1.0` stays `"1.0"` instead of collapsing to `1`.
    /// Booleans become `"true"`/`"false"`, and anything else — nested mapping, sequence, null —
    /// becomes an empty string rather than being dropped or reported.
    ///
    /// - Parameter value: The `metadata` entry, or `nil` when the skill has none.
    /// - Returns: The stringified pairs, empty when `value` is `nil` or not a mapping.
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
