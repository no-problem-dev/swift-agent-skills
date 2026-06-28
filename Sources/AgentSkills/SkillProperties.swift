import Foundation
import StructuredDataCore

/// `SKILL.md` フロントマターから解析したスキルのプロパティ。
///
/// `skills-ref` の `SkillProperties`（models.py）を移植。標準が定めるフィールドはこの 6 つのみ —
/// `name` と `description` は必須、残りはオプション。規定外のフィールドはバリデーションエラー。
public struct SkillProperties: Sendable, Equatable, Codable {
    /// ケバブケースのスキル名（必須）。
    public var name: String
    /// スキルの概要とどんな時に使うか（必須）。
    public var description: String
    /// スキルのライセンス（オプション）。
    public var license: String?
    /// 動作環境・互換性メモ（オプション）。
    public var compatibility: String?
    /// スペース区切りの事前承認済みツールパターン（オプション・実験的）。
    public var allowedTools: String?
    /// クライアント固有のキー/バリューメタデータ（デフォルトは空）。
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

    /// パース済みフロントマターからプロパティを構築する。
    ///
    /// `skills-ref` の `read_properties` と同じ必須フィールドチェックのみ実施。
    /// 完全なバリデーションは ``SkillValidator`` を使う。
    ///
    /// - Throws: `name`/`description` が欠損または空文字の場合は ``SkillValidationError``。
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

    /// `metadata` マッピングの値を文字列へ強制変換する。
    ///
    /// 参照実装の `{str(k): str(v)}` に準拠。数値はソーステキストをそのまま保持する。
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
