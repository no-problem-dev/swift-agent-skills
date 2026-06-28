# swift-agent-skills

[English](./README.md) | 日本語

[Agent Skills](https://agentskills.io)（Anthropic が開発しオープン化した `SKILL.md` 標準、Apache-2.0、`github.com/agentskills/agentskills` で管理）の Swift 準拠実装。

「プロシージャル知識を 1 つのエージェントにロードする」基本プリミティブ。A2A（エージェント間の能力アドバタイズ）や MCP（ツール接続）と相補的な存在。スキルは**プログレッシブディスクロージャーによってコンテキストにロードされる不活性なデータ**であり、サブエージェント（「fork」）での実行はオプションの非標準パターンとしてコンシューマに委ねている（`SkillExecutor` 参照）。

## ターゲット構成

依存は一方向。LLM 結合は単一の薄いターゲットに隔離している。

| ターゲット | 役割 | 依存 |
|---|---|---|
| `AgentSkills` | **厳格な標準コア** — パーサー/バリデーター/カタログ。`skills-ref`（`parser.py`/`validator.py`/`prompt.py`）を 1:1 で移植。 | `StructuredDataCore`, `YAMLParsing`, `PersistenceCore` |
| `AgentSkillsDiscovery` | **寛容なマルチルート探索**（warn-and-load）— インジェクトされたファイルシステム経由。`.agents/skills`（標準）+ `.claude/skills`（互換）、親ウォーク、トラストゲート、リソース列挙。 | `AgentSkills`, `PersistenceCore` |
| `AgentSkillsRuntime` | **ループアクティベーションロジック** — カタログレンダラー（location 非表示）、`SkillActivator`、重複排除、`SkillBodyRenderer`（Plain デフォルト）、`SkillExecutor`。LLM 依存なし。 | `AgentSkillsDiscovery` |
| `AgentSkillsTool` | **`invoke_skill` `Tool` アダプター** — 唯一の LLM 結合面。 | `AgentSkillsRuntime`, `LLMTool` |

ファイルシステムは `swift-persistence` の `FileSystemReading`（`PersistenceCore`）で抽象化。`FoundationFileSystem`（ディスク）と `InMemoryFileSystem`（テスト）を差し替え可能な実装として提供する。

## インストール（Swift Package Manager）

`Package.swift` の `dependencies` に追加する:

```swift
.package(url: "https://github.com/no-problem-dev/swift-agent-skills.git", from: "<version>")
```

使用するターゲットに必要なライブラリを追加する:

```swift
.target(
    name: "MyTarget",
    dependencies: [
        .product(name: "AgentSkillsDiscovery", package: "swift-agent-skills"),
        .product(name: "AgentSkillsRuntime", package: "swift-agent-skills"),
        .product(name: "AgentSkillsTool", package: "swift-agent-skills"),
    ]
)
```

## 使い方

### ホストへの統合（例: A2AResearchDemo）

セッション開始時にホストがスキルを探索してツールを登録する。カタログは `Tool.systemInstruction` に乗り、ループが自動注入する:

```swift
import AgentSkillsDiscovery
import AgentSkillsRuntime
import AgentSkillsTool
import PersistenceFileSystem

// 1. 探索（セキュアなデフォルト: 信頼済みプロジェクト、コマンド実行なし）
let registry = SkillRegistry(discovery: FileSystemSkillDiscovery(
    config: .init(projectRoot: projectRoot, worktreeStop: repoRoot, homeDirectory: home,
                  isTrusted: { trustStore.isTrusted($0) }),
    fileSystem: FoundationFileSystem()
))
await registry.load()

// 2. ツール → ワーカーツールリスト。InvokeSkillTool が Tool.systemInstruction でカタログを保持し、
//    ループが自動注入する（systemPrompt への手動ミューテーションは不要）。
let activator = SkillActivator(registry: registry, session: SkillSessionState())
var tools: [any Tool] = existingWorkerTools
if let skillTool = InvokeSkillTool.make(skills: await registry.available(), activator: activator) {
    tools.append(skillTool)
}
```

StudioFeature では `WorkerConfiguration.tools`（researcher/host）とシステムプロンプト組み立てに組み込む。ワーカーで fork 実行が必要な場合は `swift-agent-runtime` 上に構築したコンシューマ `SkillExecutor` を渡す。

#### リリース順序（アプリビルドの前提条件）

アプリはバージョン付き（git URL）依存を使うため、統合は次の順序で行う:

1. `swift-persistence` に新しい `FileSystemReading` を追加してリリースする（本リポジトリが依存）。
2. このパッケージの依存を `path:` からバージョン付き URL に切り替えてタグを打つ。
3. `StudioFeature/Package.swift` に `swift-agent-skills`（URL）を追加し、上記スニペットを組み込んで iOS 向けに Xcode でビルドする。

### コア API の基本的な使い方

```swift
import AgentSkills

// SKILL.md の内容をパースしてプロパティを取得する
let content = """
---
name: my-skill
description: 何かをするスキル。
---
スキル本体の Markdown。
"""

let (frontmatter, body) = try SkillFrontmatter.parseFrontmatter(content)
let properties = try SkillProperties(frontmatter: frontmatter)
print(properties.name)        // "my-skill"
print(body)                   // "スキル本体の Markdown。"

// スキルを厳密にバリデートする
let errors = SkillValidator.validate(frontmatter: frontmatter, directoryName: "my-skill")
assert(errors.isEmpty)

// SKILL.md ドキュメントを再シリアライズする
let serialized = SkillDocument.serialize(properties: properties, body: body)
```

## 公式テストによる準拠確認（TDD）

- `AgentSkills` は公式の `skills-ref` テストスイートを逐語移植して検証 — `test_parser.py`（16 件）、`test_validator.py`（24/21 件）、`test_prompt.py`（4 件）。NFKC + i18n 名前、6 つの `ALLOWED_FIELDS`、metadata 文字列化、`SKILL.md`/`skill.md` フォールバックはすべて参照実装とバイト互換。
- `AgentSkillsDiscovery` / `AgentSkillsRuntime` の動作は OpenHands（`invoke_skill`、リソースディレクトリ、name 不一致の寛容処理、優先順位）と公式クライアント実装ガイドから導出。

## セキュリティ

- **デフォルトでコマンド実行なし。** `PlainSkillRenderer` はインライン `` !`cmd` `` ブロックを実行しない。動的レンダリングは別途オプトインの `SkillBodyRenderer` として提供。
- **トラストゲート**をプロジェクトレベルルートに設ける（`SkillDiscoveryConfig.isTrusted`）— 信頼されていないクローンされたリポジトリが静かに指示を注入するのを防ぐ。
- **リソースはリストアップするだけで先読みしない** — モデルがオンデマンドでロードする。
- **カタログは `<location>` を非表示にする** — モデルは必ず `invoke_skill` を経由する必要がある。

## ライセンス

Apache License 2.0
