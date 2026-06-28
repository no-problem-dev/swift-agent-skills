import Foundation

/// セッション内で有効化済みのスキルを追跡する重複排除機構。
///
/// ループが同一スキルの指示を二重注入しないよう管理する。OpenHands の `invoked_skills` に相当。
public actor SkillSessionState {
    private var invoked: Set<String> = []

    public init() {}

    /// アクティベーションを記録する。初回アクティベーションなら `true` を返す。
    @discardableResult
    public func record(_ name: String) -> Bool {
        invoked.insert(name).inserted
    }

    /// このセッションでスキル `name` がアクティベーション済みかを返す。
    public func wasInvoked(_ name: String) -> Bool { invoked.contains(name) }

    /// このセッションでアクティベーションされた全スキル名のセット。
    public var invokedSkills: Set<String> { invoked }
}
