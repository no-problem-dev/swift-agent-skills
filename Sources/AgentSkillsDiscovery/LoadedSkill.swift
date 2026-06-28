import Foundation
import AgentSkills

/// 発見されたスキルの保存場所。
public enum SkillLocation: Sendable, Equatable, Codable {
    /// （仮想も含む）ファイルシステム上の `SKILL.md` ファイル。
    case file(URL)
    /// ホストに組み込まれたビルトインスキル。名前で識別する。
    case builtin(name: String)

    /// スキルのベースディレクトリ（`SKILL.md` の親）。
    ///
    /// `scripts/`, `references/`, `assets/` の相対パス解決に使う。ビルトインの場合は `nil`。
    public var directory: URL? {
        if case .file(let url) = self { return url.deletingLastPathComponent() }
        return nil
    }
}

/// スキルが `SKILL.md` と共に格納できる標準リソースディレクトリ群。
public struct SkillResources: Sendable, Equatable, Codable {
    public static let directoryNames = ["scripts", "references", "assets"]

    /// スキルのベースディレクトリの絶対パス。
    public let root: URL
    /// `scripts/` 配下のファイルの相対パス一覧。
    public let scripts: [String]
    /// `references/` 配下のファイルの相対パス一覧。
    public let references: [String]
    /// `assets/` 配下のファイルの相対パス一覧。
    public let assets: [String]

    public init(root: URL, scripts: [String] = [], references: [String] = [], assets: [String] = []) {
        self.root = root
        self.scripts = scripts
        self.references = references
        self.assets = assets
    }

    public var hasResources: Bool { !scripts.isEmpty || !references.isEmpty || !assets.isEmpty }
}

/// メモリにロードされた、カタログ化・アクティベーション可能なスキル。
///
/// 寛容ロード: `name` がディレクトリ名と一致しないなど厳格バリデーションに失敗しても、
/// 本体と説明が揃っていれば読み込む。厳格エラーは ``SkillDiagnostic`` の警告として記録される。
public struct LoadedSkill: Sendable, Equatable, Identifiable, Codable {
    public var id: String { name }
    public let name: String
    public let description: String
    /// スキルの Markdown 本体（フロントマターを除く）。空文字も許容される。
    public let body: String
    public let location: SkillLocation
    public let properties: SkillProperties
    /// スキルのリソースディレクトリ群（`scripts/`, `references/`, `assets/`）。ビルトインスキルや対応ディレクトリがない場合は `nil`。
    public let resources: SkillResources?

    public init(
        name: String,
        description: String,
        body: String,
        location: SkillLocation,
        properties: SkillProperties,
        resources: SkillResources? = nil
    ) {
        self.name = name
        self.description = description
        self.body = body
        self.location = location
        self.properties = properties
        self.resources = resources
    }
}

/// スキルの探索・読み込み中に発生した、致命的でない問題。
public struct SkillDiagnostic: Sendable, Equatable, Codable {
    public enum Severity: String, Sendable, Codable { case warning, error }
    public let severity: Severity
    public let location: String
    public let message: String

    public init(_ severity: Severity, location: String, message: String) {
        self.severity = severity
        self.location = location
        self.message = message
    }
}

/// 探索パスの結果。
public struct DiscoveredSkills: Sendable {
    public let skills: [LoadedSkill]
    public let diagnostics: [SkillDiagnostic]
    public init(skills: [LoadedSkill], diagnostics: [SkillDiagnostic]) {
        self.skills = skills
        self.diagnostics = diagnostics
    }
}
