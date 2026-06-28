import Foundation
import AgentSkillsDiscovery

/// コンテキスト注入直前にスキルの本体をレンダリングするプロトコル。
///
/// デフォルト実装は ``PlainSkillRenderer``（本体をそのまま返す）。
/// インライン `` !`cmd` `` ブロックを実行する動的レンダリングは別途オプトイン実装として提供する —
/// スキルコンテンツからのシェル実行は最高リスクの攻撃面であるため、決してデフォルトにしない。
public protocol SkillBodyRenderer: Sendable {
    /// スキル本体をコンテキスト注入向けにレンダリングして返す。
    ///
    /// - Parameter skill: レンダリング対象のスキル。
    /// - Parameter workingDirectory: 動的レンダラーが相対パスを解決する際の作業ディレクトリ。不要な場合は無視してよい。
    /// - Returns: コンテキストに注入するレンダリング済み本体テキスト。
    /// - Throws: 動的レンダリング（シェル実行など）に失敗した場合。``PlainSkillRenderer`` は throw しない。
    func render(_ skill: LoadedSkill, workingDirectory: URL?) async throws -> String
}

/// コマンド実行なしで本体をそのまま返すアイデンティティレンダラー。セキュアなデフォルト実装。
public struct PlainSkillRenderer: SkillBodyRenderer {
    public init() {}
    public func render(_ skill: LoadedSkill, workingDirectory: URL?) async throws -> String {
        skill.body
    }
}
