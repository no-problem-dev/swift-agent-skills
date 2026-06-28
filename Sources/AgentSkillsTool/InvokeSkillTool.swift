import Foundation
import LLMClient
import LLMTool
import AgentSkillsDiscovery
import AgentSkillsRuntime

/// エージェントループが登録する `invoke_skill` ツール — `systemInstruction` に Tier-1 `<available_skills>` カタログを乗せるための一級 `Tool`。
///
/// OpenHands が `agent_context.skills` から別々に導出する 2 つの要素（カタログ → システムメッセージ・自動アタッチツール）を
/// 構造上で統一する: `[LoadedSkill]` の単一スナップショットが、カタログ（`Tool.systemInstruction` 経由でループが注入）と
/// `name` 列挙の両方を生成する。モデルが見えるスキルと呼び出せるスキルは必ず一致する。
public struct InvokeSkillTool: Tool {

    public static let toolName = "invoke_skill"

    private let availableNames: [String]
    private let activator: SkillActivator
    private let executor: any SkillExecutor
    private let catalog: String?

    public var toolName: String { Self.toolName }

    public var toolDescription: String {
        """
        Invoke a skill by name to load its full instructions. This is the only \
        supported way to activate a skill listed in <available_skills>. Call it \
        with the exact name shown there; the skill's full content is returned.
        """
    }

    public var inputSchema: JSONSchema {
        JSONSchema.object(fields: [
            JSONSchema.enum(
                availableNames,
                description: "The name of the skill from <available_skills>."
            ).named("name")
        ])
    }

    /// カタログは `Tool.systemInstruction` としてループが自動的にシステムプロンプトへ注入する。
    public var systemInstruction: String? { catalog }

    /// `name` パラメーターをデコードしてスキルをアクティベートし、実行結果を返す。
    ///
    /// - JSON デコード失敗または `name` が空: `.error("Missing required parameter 'name'.")` を返す（throw しない）。
    /// - `.activated`: executor でスキルを実行し `.text(content)` を返す。
    /// - `.unknown`: `.error` に利用可能スキル名一覧を付けて返す。
    /// - `.notModelInvocable`: `.error` でトリガー専用である旨を返す。
    public func execute(with argumentsData: Data) async throws -> ToolResult {
        let name: String
        if let decoded = try? JSONDecoder().decode(Input.self, from: argumentsData), !decoded.name.isEmpty {
            name = decoded.name
        } else {
            return .error("Missing required parameter 'name'.")
        }

        let outcome = try await activator.activate(name: name)
        switch outcome {
        case .activated(let content, _):
            switch try await executor.run(Self.identity(name), renderedContent: content) {
            case .inline(let text): return .text(text)
            case .forked(let summary): return .text(summary)
            }
        case .unknown(let available):
            return .error("Unknown skill '\(name)'. Available skills: \(available.joined(separator: ", ")).")
        case .notModelInvocable(let blocked):
            return .error("Skill '\(blocked)' cannot be invoked directly; it is trigger-only.")
        }
    }

    private struct Input: Decodable { let name: String }

    // MARK: - Construction

    /// 利用可能スキルのスナップショットからツールを構築する — カタログと `name` 列挙の単一ソース。
    ///
    /// スキルが 0 件なら `nil`（空のツール・カタログを登録しないため）。
    public static func make(
        skills: [LoadedSkill],
        activator: SkillActivator,
        catalogRenderer: SkillCatalogRenderer = SkillCatalogRenderer(),
        executor: any SkillExecutor = InlineSkillExecutor()
    ) -> InvokeSkillTool? {
        guard !skills.isEmpty else { return nil }
        let names = skills.map(\.name).sorted()
        let catalog = catalogRenderer.render(skills).map {
            catalogRenderer.instructions(toolName: toolName) + "\n" + $0
        }
        return InvokeSkillTool(availableNames: names, activator: activator, executor: executor, catalog: catalog)
    }

    /// インラインエグゼキューターはスキルの identity のみ必要 — ツール層での 2 回目のレジストリ検索を避ける。
    private static func identity(_ name: String) -> LoadedSkill {
        LoadedSkill(
            name: name, description: "", body: "",
            location: .builtin(name: name),
            properties: .init(name: name, description: "")
        )
    }
}
