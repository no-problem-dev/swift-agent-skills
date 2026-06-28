# ``AgentSkillsDiscovery``

ファイルシステムをスキャンしてスキルを寛容に読み込む探索層 — 登録・書き込みまでを一括で担う。

## Overview

`AgentSkillsDiscovery` はファイルシステム上の `SKILL.md` を検出し、
バリデーションエラーがあっても読み込み可能な限り**寛容に（warn-and-load）**ロードする。
OpenHands の探索仕様と公式クライアントガイドを移植した設計。

ファイルシステム依存は `FileSystemReading` / `FileSystemWriting` プロトコル
（`swift-persistence` の `PersistenceCore` ）に集約されているため、
本番環境では実 OS ファイルシステムを、テスト環境ではインメモリ実装を差し込んで使える。

### スキルの探索と読み込み

`SkillDiscoveryConfig` で探索ルートを設定し、`FileSystemSkillDiscovery` を使って `discover()` を呼ぶと
`DiscoveredSkills` が返る。複数ルートで同名スキルがあった場合は `SkillScope`
（`explicit > project > user`）で上位のものが優先され、衝突は `SkillDiagnostic` として記録される。

```swift
import AgentSkillsDiscovery
import PersistenceFileSystem

let config = SkillDiscoveryConfig(
    projectRoot: URL(filePath: "/path/to/project"),
    homeDirectory: FileManager.default.homeDirectoryForCurrentUser
)
let discovery = FileSystemSkillDiscovery(config: config, fileSystem: RealFileSystem())
let result = await discovery.discover()
print(result.skills.map(\.name))       // 見つかったスキル名の一覧
print(result.diagnostics)              // 警告・エラー
```

### スキルレジストリ

`SkillRegistry` は探索結果をキャッシュし、`SkillPolicy` によるフィルタリングを提供する。
ビルトインスキルをシードしてから、ディスク上のスキルで上書きするパターン
（ユーザーがビルトインを同名スキルで差し替えられる）を実装している。

```swift
let registry = SkillRegistry(discovery: discovery)
await registry.load()
let skill = await registry.get("my-skill")
let visible = await registry.available()   // ポリシーでフィルタ済み
```

### スキルの作成・更新・削除

`SkillWriter` は書き込み操作を担う。`SkillDocument.serialize` で生成した内容を
インジェクトされた `FileSystemWriting` バックエンドへ永続化する。

```swift
let writer = SkillWriter(root: skillsRoot, fileSystem: RealFileSystem())
let props = SkillProperties(name: "new-skill", description: "新しいスキル。")
try await writer.create(properties: props, body: "# Instructions\n...")
```

## Topics

### 探索プロトコルと設定

- ``SkillDiscovering``
- ``SkillDiscoveryConfig``
- ``SkillScope``
- ``FileSystemSkillDiscovery``

### 読み込み結果の型

- ``LoadedSkill``
- ``SkillLocation``
- ``SkillResources``
- ``DiscoveredSkills``
- ``SkillDiagnostic``

### レジストリ

- ``SkillRegistry``
- ``SkillPolicy``

### 書き込み

- ``SkillWriter``
- ``SkillWriteError``
