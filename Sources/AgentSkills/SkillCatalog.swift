import Foundation
import PersistenceCore

/// エージェントのシステムプロンプト向け `<available_skills>` XML ブロックを生成する。
///
/// `skills-ref` prompt.py をバイトレベルで移植した参照実装。`<location>` を**含む**仕様準拠形式。
/// ツール経由のアクティベーションを強制したい場合は、ランタイム層の location を省略する変形を使う。
public enum SkillCatalog {

    /// 指定したスキルディレクトリ群からカタログブロックを生成する。
    ///
    /// - Throws: いずれかのスキルの `SKILL.md` を読み込めない場合は ``SkillParseError`` または ``SkillValidationError``。
    public static func toPrompt(
        skillDirectories: [URL],
        fileSystem: some FileSystemReading
    ) async throws -> String {
        if skillDirectories.isEmpty {
            return "<available_skills>\n</available_skills>"
        }

        var lines = ["<available_skills>"]
        for directory in skillDirectories {
            let resolved = directory.standardizedFileURL
            let props = try await SkillFrontmatter.readProperties(from: resolved, fileSystem: fileSystem)

            lines.append("<skill>")
            lines.append("<name>")
            lines.append(htmlEscape(props.name))
            lines.append("</name>")
            lines.append("<description>")
            lines.append(htmlEscape(props.description))
            lines.append("</description>")

            let manifest = await SkillFrontmatter.findSkillMD(in: resolved, fileSystem: fileSystem)
            lines.append("<location>")
            lines.append(manifest?.path ?? "")
            lines.append("</location>")

            lines.append("</skill>")
        }
        lines.append("</available_skills>")
        return lines.joined(separator: "\n")
    }

    /// Python `html.escape(quote=True)` と同等: `& < > " '` をエスケープする。
    private static func htmlEscape(_ string: String) -> String {
        var result = string.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#x27;")
        return result
    }
}
