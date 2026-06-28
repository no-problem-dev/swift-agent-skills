import Foundation

/// ロード済みスキルのインメモリカタログ。
///
/// ビルトインを先にシードし、同名のディスクスキルで上書きする —
/// OpenCode/OpenHands の「先にビルトインを登録し、ユーザースキルで差し替えられる」仕様に準拠。
public actor SkillRegistry {
    private var skills: [String: LoadedSkill] = [:]
    private let builtins: [LoadedSkill]
    private let discovery: (any SkillDiscovering)?
    public private(set) var diagnostics: [SkillDiagnostic] = []

    public init(builtins: [LoadedSkill] = [], discovery: (any SkillDiscovering)? = nil) {
        self.builtins = builtins
        self.discovery = discovery
    }

    /// ビルトインをシードし、次に探索スキルを読み込んで上書きする。
    public func load() async {
        skills.removeAll()
        diagnostics.removeAll()
        for skill in builtins {
            skills[skill.name] = skill
        }
        if let discovery {
            let discovered = await discovery.discover()
            diagnostics = discovered.diagnostics
            for skill in discovered.skills {
                skills[skill.name] = skill  // disk overrides builtin
            }
        }
    }

    /// 名前でスキルを取得する。``load()`` 実行前は常に `nil`。
    public func get(_ name: String) -> LoadedSkill? { skills[name] }

    /// 全スキルを名前順で返す。ポリシーフィルタなし（``available(policy:)`` と異なる）。``load()`` 実行前は空。
    public func all() -> [LoadedSkill] { skills.values.sorted { $0.name < $1.name } }

    /// ポリシーでフィルタしたモデルに見せるスキル一覧。非表示スキルはアクティベーション拒否ではなくカタログから除外する。
    public func available(policy: SkillPolicy = .init()) -> [LoadedSkill] {
        all().filter { policy.isAllowed($0.name) }
    }
}

/// モデルにアドバタイズするスキルを絞り込むポリシー。
public struct SkillPolicy: Sendable {
    public let isAllowed: @Sendable (_ name: String) -> Bool
    public init(isAllowed: @escaping @Sendable (_ name: String) -> Bool = { _ in true }) {
        self.isAllowed = isAllowed
    }
}
