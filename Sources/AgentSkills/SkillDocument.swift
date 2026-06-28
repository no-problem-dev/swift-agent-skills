import Foundation
import StructuredDataCore
import YAMLParsing

/// `SKILL.md` のオーサリング側 — ``SkillFrontmatter`` パースの逆操作。
///
/// ``SkillProperties`` を仕様準拠のフロントマターおよびフル `SKILL.md` ドキュメントへシリアライズする。
/// ファイルシステム不要のピュア実装で、`parseFrontmatter(serialize(p, body))` により `p` と `body` を復元できる。
/// ディスク書き込みは `AgentSkillsDiscovery` の `SkillWriter` が担う。
public enum SkillDocument {

    private static let serializer = YAMLSerializer(options: .init(sortKeys: false))

    /// 仕様が定める標準順序でフロントマターマッピングを構築する。
    ///
    /// 未設定のオプションフィールドは省略する。`metadata` のキーは決定論的出力のためソートする。
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

    /// フロントマターマッピングを YAML テキストへシリアライズする（`---` フェンスなし）。
    public static func frontmatterYAML(_ properties: SkillProperties) -> String {
        serializer.string(from: .object(frontmatter(properties)))
    }

    /// 完全な `SKILL.md` ドキュメントをシリアライズする。フェンス付きフロントマターとマークダウン本体を連結する。
    public static func serialize(properties: SkillProperties, body: String) -> String {
        let yaml = frontmatterYAML(properties)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.isEmpty {
            return "---\n" + yaml + "---\n"
        }
        return "---\n" + yaml + "---\n\n" + trimmedBody + "\n"
    }

    /// オーサリング用の厳格バリデーションゲート。`skills-ref validate` と同じルールで検証し、エラー文字列の配列を返す（空 = 有効）。
    public static func validate(_ properties: SkillProperties) -> [String] {
        SkillValidator.validate(frontmatter: frontmatter(properties), directoryName: properties.name)
    }
}
