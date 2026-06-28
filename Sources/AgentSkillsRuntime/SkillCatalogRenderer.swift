import Foundation
import AgentSkillsDiscovery

/// システムプロンプト向け Tier-1 `<available_skills>` カタログをレンダリングする。
///
/// 仕様互換の `AgentSkills.SkillCatalog` とは別の本番バリアント。
/// デフォルトでは `<location>` を**省略**し、モデルがファイルを直接読んでアクティベーションツールを
/// バイパスするのを防ぐ（OpenHands の動作に準拠）。
public struct SkillCatalogRenderer: Sendable {
    /// `<location>` タグをカタログに含めるか（デフォルト: `false` — モデルがファイルを直接読んでアクティベーションをバイパスするのを防ぐ）。
    public var includeLocation: Bool
    /// カタログ内 description の最大文字数（デフォルト: 1024 文字。超過分は切り捨て）。
    public var maxDescriptionLength: Int

    public init(includeLocation: Bool = false, maxDescriptionLength: Int = 1024) {
        self.includeLocation = includeLocation
        self.maxDescriptionLength = maxDescriptionLength
    }

    /// `<available_skills>` ブロックを返す。スキルが 0 件なら `nil`（空ブロックを表示しないためループが省略できる）。
    public func render(_ skills: [LoadedSkill]) -> String? {
        guard !skills.isEmpty else { return nil }
        var lines = ["<available_skills>"]
        for skill in skills.sorted(by: { $0.name < $1.name }) {
            lines.append("  <skill>")
            lines.append("    <name>\(escape(skill.name))</name>")
            lines.append("    <description>\(escape(truncate(skill.description)))</description>")
            if includeLocation, case .file(let url) = skill.location {
                lines.append("    <location>\(escape(url.path))</location>")
            }
            lines.append("  </skill>")
        }
        lines.append("</available_skills>")
        return lines.joined(separator: "\n")
    }

    /// スキルのアクティベーション方法をモデルに伝える短い指示ブロック。
    public func instructions(toolName: String) -> String {
        """
        The following skills provide specialized instructions for specific tasks. \
        When a task matches a skill's description, call the \(toolName) tool with the \
        skill's name to load its full instructions.
        """
    }

    private func truncate(_ text: String) -> String {
        guard text.count > maxDescriptionLength else { return text }
        return String(text.prefix(maxDescriptionLength))
    }

    private func escape(_ string: String) -> String {
        var result = string.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        return result
    }
}
