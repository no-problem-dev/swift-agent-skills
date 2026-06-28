import Foundation
import AgentSkillsDiscovery

/// アクティベーション後のスキル実行戦略を定義するプロトコル。
///
/// 標準の組み込みパスは**インライン**: レンダリング済み本体を現在の会話に注入する。
/// サブエージェントの別セッションで実行する「fork」は一部クライアントのみが対応する任意パターンであり、
/// Agent Skills 標準には含まれない — コンシューマが実装を注入することでこのパッケージをエージェントランタイム非依存に保つ。
public protocol SkillExecutor: Sendable {
    func run(_ skill: LoadedSkill, renderedContent: String) async throws -> SkillExecutionResult
}

/// スキル実行の結果。
public enum SkillExecutionResult: Sendable, Equatable {
    /// コンテンツを現在の会話に注入する（デフォルトのパス）。
    case inline(content: String)
    /// サブエージェントがスキルを実行して生成したサマリー（コンシューマ提供）。
    case forked(summary: String)
}

/// 組み込みインラインエグゼキューター: レンダリング済みコンテンツを会話内注入用に返す。このパッケージが提供する唯一のエグゼキューター。
public struct InlineSkillExecutor: SkillExecutor {
    public init() {}
    public func run(_ skill: LoadedSkill, renderedContent: String) async throws -> SkillExecutionResult {
        .inline(content: renderedContent)
    }
}
