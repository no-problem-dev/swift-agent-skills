# ``AgentSkills``

SKILL.md オープン標準の Swift 実装コア — パース・バリデーション・シリアライズ・カタログ生成を担うピュア層。

## Overview

`AgentSkills` は [Agent Skills 標準](https://agentskills.io) の Swift 移植。
`SKILL.md` フロントマターのパース・バリデーション・シリアライズ、
そしてエージェントのシステムプロンプトへ注入する `<available_skills>` カタログ生成を担う。

このモジュールは一切の副作用を持たない**ピュア層**。
ファイルシステムへの直接アクセスは行わず、`FileSystemReading` プロトコルを介したインジェクション形式を取る。
そのため単体テストでインメモリ実装を差し込むことができ、CLI・サーバーの両環境で安全に利用できる。

### パッケージの構成

`swift-agent-skills` パッケージは 4 つのライブラリから成る。
このモジュール（`AgentSkills`）が土台で、残り 3 つがそれぞれの役割を担う。

ファイルシステムからスキルをスキャンして読み込む探索層は **`AgentSkillsDiscovery`** が担う。
`FileSystemSkillDiscovery` によるマルチルート探索、`SkillRegistry` によるスキルの保持と検索、
`SkillWriter` によるスキル作成・更新・削除が含まれる。

スキルを有効化してエージェントループへ注入する実行層は **`AgentSkillsRuntime`** が担う。
`SkillActivator` による名前解決と重複排除、`SkillCatalogRenderer` による `<available_skills>` ブロックのレンダリング、
`SkillSessionState` によるセッション内アクティベーション履歴の管理が含まれる。
このモジュールも LLM スタックへの依存を持たないピュア層。

LLM ツールとしての統合層は **`AgentSkillsTool`** が担う。
`InvokeSkillTool` 1 つだけが `swift-llm-client` の `Tool` プロトコルに準拠し、
カタログと `name` 列挙を単一のスナップショットから生成する。

### 基本的な使い方

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

## Topics

### スキルプロパティ

- ``SkillProperties``

### パース

- ``SkillFrontmatter``

### バリデーション

- ``SkillValidator``

### シリアライズ（オーサリング）

- ``SkillDocument``

### カタログ生成

- ``SkillCatalog``

### エラー

- ``SkillParseError``
- ``SkillValidationError``
