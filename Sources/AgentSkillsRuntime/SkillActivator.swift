import Foundation
import AgentSkills
import AgentSkillsDiscovery

/// スキルをアクティベートしようとした結果。
public enum SkillActivationOutcome: Sendable, Equatable {
    /// 注入可能なレンダリング済みスキルコンテンツ。`alreadyActive` が `true` なら再アクティベーション（ループは再注入をスキップできる）。
    case activated(content: String, alreadyActive: Bool)
    /// 指定名のアドバタイズ済みスキルが存在しない。モデル向けにソート済みの利用可能名を保持する。
    case unknown(available: [String])
    /// スキルは存在するが、モデルから直接呼び出せないトリガー専用スキル。
    case notModelInvocable(name: String)
}

/// Tier-2 アクティベーション: スキル名を解決し、本体をレンダリングして会話向けにラップし、重複排除のために記録する。
///
/// LLM スタック非依存のピュア実装 — レジストリ・ボディレンダラー・セッション状態のみ必要。
/// `Tool` アダプターは `AgentSkillsTool` に分離している。
public struct SkillActivator: Sendable {
    private let registry: SkillRegistry
    private let renderer: any SkillBodyRenderer
    private let session: SkillSessionState
    private let policy: SkillPolicy
    private let workingDirectory: URL?

    /// `workingDirectory` は ``SkillBodyRenderer/render(_:workingDirectory:)`` に渡す。
    /// 動的レンダラーがスキル内の相対パスを解決する際に参照する。`nil` の場合はレンダラーがデフォルトを決める。
    public init(
        registry: SkillRegistry,
        renderer: any SkillBodyRenderer = PlainSkillRenderer(),
        session: SkillSessionState = SkillSessionState(),
        policy: SkillPolicy = .init(),
        workingDirectory: URL? = nil
    ) {
        self.registry = registry
        self.renderer = renderer
        self.session = session
        self.policy = policy
        self.workingDirectory = workingDirectory
    }

    /// スキル名を解決し、本体をレンダリングして結果を返す。
    ///
    /// - `registry.get(name)` が `nil` → `.unknown(available:)` を返す。ポリシーでフィルタした利用可能スキル名一覧を付与する。
    /// - `policy.isAllowed(name)` が `false` → `.notModelInvocable(name:)` を返す。スキルはトリガー専用でモデルから直接呼び出せない。
    /// - それ以外 → `.activated(content:alreadyActive:)` を返す。`alreadyActive` はこのセッションで既にアクティベーション済みかどうかを示す（ループが再注入をスキップする判断に使える）。
    ///
    /// - Throws: ``SkillBodyRenderer/render(_:workingDirectory:)`` が throw した場合に伝播する。
    public func activate(name rawName: String) async throws -> SkillActivationOutcome {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let skill = await registry.get(name) else {
            let available = await registry.available(policy: policy).map(\.name)
            return .unknown(available: available)
        }
        guard policy.isAllowed(name) else {
            return .notModelInvocable(name: name)
        }

        let body = try await renderer.render(skill, workingDirectory: workingDirectory)
        let content = wrap(skill: skill, body: body)
        let isFirst = await session.record(name)
        return .activated(content: content, alreadyActive: !isFirst)
    }

    /// レンダリング済み本体を `<skill_content>` でラップし、ベースディレクトリフッターとリソースファイル一覧を付与する（OpenCode/OpenHands 形式）。
    private func wrap(skill: LoadedSkill, body: String) -> String {
        var lines = ["<skill_content name=\"\(skill.name)\">"]
        lines.append(body.trimmingCharacters(in: .whitespacesAndNewlines))

        if case .file(let manifest) = skill.location {
            let dir = manifest.deletingLastPathComponent().path
            lines.append("")
            lines.append("Base directory for this skill: \(dir)")
            lines.append("Relative paths (e.g. scripts/, references/, assets/) are relative to that directory.")
        }

        if let resources = skill.resources, resources.hasResources {
            lines.append("<skill_files>")
            for file in resources.scripts + resources.references + resources.assets {
                lines.append("<file>\(file)</file>")
            }
            lines.append("</skill_files>")
        }

        lines.append("</skill_content>")
        return lines.joined(separator: "\n")
    }
}
