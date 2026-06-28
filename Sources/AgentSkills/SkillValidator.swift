import Foundation
import StructuredDataCore
import PersistenceCore

/// Agent Skills 標準に準拠した厳格バリデーター。
///
/// `skills-ref` validator.py を移植。エラーメッセージは参照実装と逐語的に一致し、
/// `skills-ref validate` と同一の出力を返す。エラーなし（空配列）= 有効。
public enum SkillValidator {

    public static let maxNameLength = 64
    public static let maxDescriptionLength = 1024
    public static let maxCompatibilityLength = 500

    /// Agent Skills 仕様が許可するフロントマターフィールド。
    public static let allowedFields: Set<String> = [
        "name", "description", "license", "allowed-tools", "metadata", "compatibility",
    ]

    /// スキルディレクトリの `SKILL.md` を読み込んで検証する。
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

    /// パース済みフロントマターを検証する。ファイルシステム不要のピュア関数。
    ///
    /// - Parameter directoryName: `name` とディレクトリ名の一致チェックに使うスキルディレクトリ名。
    ///   `nil` を渡すとチェックをスキップする。
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
