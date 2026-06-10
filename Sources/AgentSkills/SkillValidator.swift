import Foundation
import StructuredDataCore
import PersistenceCore

/// Strict Agent Skills standard validator.
///
/// Ports `skills-ref` validator.py. Returns a list of human-readable error
/// strings (empty = valid), reproduced verbatim from the reference so output
/// matches `skills-ref validate`.
public enum SkillValidator {

    public static let maxNameLength = 64
    public static let maxDescriptionLength = 1024
    public static let maxCompatibilityLength = 500

    /// Frontmatter fields permitted by the Agent Skills spec.
    public static let allowedFields: Set<String> = [
        "name", "description", "license", "allowed-tools", "metadata", "compatibility",
    ]

    /// Validates a skill directory by reading and checking its `SKILL.md`.
    public static func validate(
        skillDirectory: URL,
        fileSystem: some FileSystemReading
    ) async -> [String] {
        guard await fileSystem.exists(skillDirectory) else {
            return ["Path does not exist: \(skillDirectory.path)"]
        }
        guard await fileSystem.isDirectory(skillDirectory) else {
            return ["Not a directory: \(skillDirectory.path)"]
        }
        guard let manifest = await SkillFrontmatter.findSkillMD(in: skillDirectory, fileSystem: fileSystem) else {
            return ["Missing required file: SKILL.md"]
        }
        let frontmatter: OrderedObject
        do {
            let content = try await fileSystem.readString(manifest)
            (frontmatter, _) = try SkillFrontmatter.parseFrontmatter(content)
        } catch let error as SkillParseError {
            return [error.message]
        } catch {
            return [String(describing: error)]
        }
        return validate(frontmatter: frontmatter, directoryName: skillDirectory.lastPathComponent)
    }

    /// Validates already-parsed frontmatter. Pure — no filesystem.
    ///
    /// - Parameter directoryName: the skill directory's name, for the
    ///   name/directory match check; pass `nil` to skip it.
    public static func validate(frontmatter: OrderedObject, directoryName: String?) -> [String] {
        var errors: [String] = []

        let extraFields = Set(frontmatter.keys).subtracting(allowedFields)
        if !extraFields.isEmpty {
            errors.append(
                "Unexpected fields in frontmatter: \(extraFields.sorted().joined(separator: ", ")). "
                + "Only \(allowedFields.sorted()) are allowed."
            )
        }

        if frontmatter["name"] == nil {
            errors.append("Missing required field in frontmatter: name")
        } else {
            errors.append(contentsOf: validateName(frontmatter["name"], directoryName: directoryName))
        }

        if frontmatter["description"] == nil {
            errors.append("Missing required field in frontmatter: description")
        } else {
            errors.append(contentsOf: validateDescription(frontmatter["description"]))
        }

        if let compatibility = frontmatter["compatibility"] {
            errors.append(contentsOf: validateCompatibility(compatibility))
        }

        return errors
    }

    private static func validateName(_ value: StructuredValue?, directoryName: String?) -> [String] {
        guard let raw = value?.string, !raw.trimmed.isEmpty else {
            return ["Field 'name' must be a non-empty string"]
        }
        var errors: [String] = []
        let name = raw.trimmed.precomposedStringWithCompatibilityMapping  // NFKC

        if name.count > maxNameLength {
            errors.append("Skill name '\(name)' exceeds \(maxNameLength) character limit (\(name.count) chars)")
        }
        if name != name.lowercased() {
            errors.append("Skill name '\(name)' must be lowercase")
        }
        if name.hasPrefix("-") || name.hasSuffix("-") {
            errors.append("Skill name cannot start or end with a hyphen")
        }
        if name.contains("--") {
            errors.append("Skill name cannot contain consecutive hyphens")
        }
        if !name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) {
            errors.append("Skill name '\(name)' contains invalid characters. Only letters, digits, and hyphens are allowed.")
        }
        if let directoryName {
            let normalizedDir = directoryName.precomposedStringWithCompatibilityMapping
            if normalizedDir != name {
                errors.append("Directory name '\(directoryName)' must match skill name '\(name)'")
            }
        }
        return errors
    }

    private static func validateDescription(_ value: StructuredValue?) -> [String] {
        guard let description = value?.string, !description.trimmed.isEmpty else {
            return ["Field 'description' must be a non-empty string"]
        }
        if description.count > maxDescriptionLength {
            return ["Description exceeds \(maxDescriptionLength) character limit (\(description.count) chars)"]
        }
        return []
    }

    private static func validateCompatibility(_ value: StructuredValue?) -> [String] {
        guard let compatibility = value?.string else {
            return ["Field 'compatibility' must be a string"]
        }
        if compatibility.count > maxCompatibilityLength {
            return ["Compatibility exceeds \(maxCompatibilityLength) character limit (\(compatibility.count) chars)"]
        }
        return []
    }
}
