import Foundation
import StructuredDataCore
import YAMLParsing
import PersistenceCore

/// `SKILL.md` の YAML フロントマターパーサー。
///
/// `skills-ref` parser.py を移植。``parseFrontmatter(_:)`` はファイルシステム不要のピュア関数。
/// ディレクトリ起点の API は ``FileSystemReading`` をインジェクションで受け取るため、
/// インメモリ実装への差し替えとテストが容易。
public enum SkillFrontmatter {

    private static let yaml = YAMLParser()

    /// `SKILL.md` の内容をフロントマターとマークダウン本体に分割する。
    ///
    /// - Throws: フロントマターが存在しない・閉じていない・不正な YAML・マッピングでない場合は ``SkillParseError``。
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

    /// スキルマニフェストを検索する。`SKILL.md` を `skill.md` より優先する。
    public static func findSkillMD(in skillDirectory: URL, fileSystem: some FileSystemReading) async -> URL? {
        for name in ["SKILL.md", "skill.md"] {
            let candidate = skillDirectory.appendingPathComponent(name)
            if await fileSystem.exists(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// スキルディレクトリの `SKILL.md` からプロパティを読み込む。
    ///
    /// 完全なバリデーションは行わない（``SkillValidator`` を使うこと）。
    ///
    /// - Throws: マニフェストが存在しないか不正な場合は ``SkillParseError``、
    ///   `name`/`description` が欠損する場合は ``SkillValidationError``。
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
