import Foundation
import AgentSkills
import PersistenceCore

/// スキルのディスク書き込み時にスローされるエラー。
public enum SkillWriteError: Error, Equatable {
    /// 厳格バリデーション失敗。バリデーターのメッセージを保持する。
    case validationFailed([String])
    /// 対象名のスキルディレクトリが既に存在する。
    case nameCollision(String)
    /// 更新・削除対象のスキルが存在しない。
    case notFound(String)
}

/// ルートディレクトリ配下へユーザー作成スキルを書き込む — ``FileSystemSkillDiscovery`` の書き込み側。
///
/// ``SkillDocument`` で厳格バリデーションを経てから ``SkillProperties`` をシリアライズし、
/// インジェクトされた ``FileSystemWriting`` バックエンドへ永続化する。
/// テスト時はインメモリ実装に差し替え可能。スキルは `<root>/<name>/SKILL.md` に格納され、
/// リネーム時はディレクトリごと移動するためリソースファイル（`scripts/`, `references/`, `assets/`）が保持される。
public struct SkillWriter<FS: FileSystemReading & FileSystemWriting>: Sendable {

    /// ユーザースキルのルートディレクトリ。例: `~/Documents/.agents/skills`。
    public let root: URL
    public let fileSystem: FS

    public init(root: URL, fileSystem: FS) {
        self.root = root
        self.fileSystem = fileSystem
    }

    private func directory(_ name: String) -> URL {
        root.appendingPathComponent(name, isDirectory: true)
    }

    private func manifest(_ name: String) -> URL {
        directory(name).appendingPathComponent("SKILL.md")
    }

    /// 新しいスキルを作成する。バリデーション後、同名スキルが存在すれば失敗する。
    public func create(properties: SkillProperties, body: String) async throws {
        try validate(properties)
        guard await fileSystem.exists(directory(properties.name)) == false else {
            throw SkillWriteError.nameCollision(properties.name)
        }
        try await fileSystem.write(SkillDocument.serialize(properties: properties, body: body),
                                   to: manifest(properties.name))
    }

    /// 既存スキルを更新する。リネームする場合はマニフェスト書き直しの前にディレクトリを移動（リソースを保持）する。
    public func update(originalName: String, properties: SkillProperties, body: String) async throws {
        try validate(properties)
        guard await fileSystem.exists(directory(originalName)) else {
            throw SkillWriteError.notFound(originalName)
        }
        if properties.name != originalName {
            guard await fileSystem.exists(directory(properties.name)) == false else {
                throw SkillWriteError.nameCollision(properties.name)
            }
            try await fileSystem.moveItem(from: directory(originalName), to: directory(properties.name))
        }
        try await fileSystem.write(SkillDocument.serialize(properties: properties, body: body),
                                   to: manifest(properties.name))
    }

    /// スキルディレクトリを削除する。存在しない場合は何もしない。
    public func delete(name: String) async throws {
        try await fileSystem.removeItem(directory(name))
    }

    private func validate(_ properties: SkillProperties) throws {
        let errors = SkillDocument.validate(properties)
        guard errors.isEmpty else { throw SkillWriteError.validationFailed(errors) }
    }
}
