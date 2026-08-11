# swift-agent-skills

[English](./README.md) | 日本語

手順書を並べたフォルダをエージェントに渡し、必要になった 1 つだけを読み込ませる。全部をシステムプロンプトに抱えさせない。

> **非公式。** Agent Skills 標準の作者とは無関係であり、承認も受けていない。仕様への準拠はこのプロジェクトの目標ではない。

## 概要

[Agent Skills](https://agentskills.io) — オープンな `SKILL.md` 形式（Anthropic 発、Apache-2.0、
`github.com/agentskills/agentskills` で管理）の Swift 実装。スキルとは、指示書と補助ファイルを収めた
ディレクトリのこと。エージェントには「何があるか」の短いカタログだけが見え、実際に使うと決めたときに
初めて本文が読み込まれる。

- **プロンプトが太らない** — モデルが最初に読むのはスキル 1 つにつき 1 行。本文は必要時に要求するので、
  20 個あっても目次 1 枚ぶんの費用で済む
- **スキルは不活性なテキスト** — 読み込んでもコンテキストに文字列が入るだけ。既定のレンダラは
  インラインの `` !`cmd` `` を実行しない
- **信頼していないチェックアウトから指示を差し込まれない** — プロジェクト直下のスキル置き場は
  トラストゲートを通る。リポジトリを clone しただけでエージェントのプロンプトを渡すことにはならない
- **補助ファイルは列挙されるだけで読まれない** — スクリプトや参考資料はモデルが要求できるパスとして
  現れる。大きなスキルディレクトリが一度に流れ込むことはない
- **作者が既に置いている場所を見る** — `.agents/skills` と `.claude/skills` を、プロジェクトから
  上へ辿りながら探索。同名ならプロジェクト側がユーザー側を上書きする
- **ファイルシステムは差し替えられる** — 本番は実ディスク、テストはインメモリ、コードは同じ

## クイックスタート

ディスク上のスキルを発見し、ループに 1 つのツールとして見せる:

```swift
import AgentSkillsDiscovery
import AgentSkillsRuntime
import AgentSkillsTool
import PersistenceFileSystem

let registry = SkillRegistry(discovery: FileSystemSkillDiscovery(
    config: .init(projectRoot: projectRoot, worktreeStop: repoRoot, homeDirectory: home,
                  isTrusted: { trustStore.isTrusted($0) }),
    fileSystem: FoundationFileSystem()
))
await registry.load()

let activator = SkillActivator(registry: registry, session: SkillSessionState())
if let skillTool = InvokeSkillTool.make(skills: await registry.available(), activator: activator) {
    tools.append(skillTool)   // カタログは Tool.systemInstruction に載る
}
```

## ドキュメント

[**AgentSkills**](https://no-problem-dev.github.io/swift-agent-skills/documentation/agentskills/) — 解析・検証・直列化 ·
[**AgentSkillsDiscovery**](https://no-problem-dev.github.io/swift-agent-skills/documentation/agentskillsdiscovery/) — 探索先・優先順位・トラストゲート ·
[**AgentSkillsRuntime**](https://no-problem-dev.github.io/swift-agent-skills/documentation/agentskillsruntime/) — カタログ描画とアクティベーション ·
[**AgentSkillsTool**](https://no-problem-dev.github.io/swift-agent-skills/documentation/agentskillstool/) — `invoke_skill` ツールアダプタ

## インストール

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-agent-skills.git", .upToNextMinor(from: "0.4.0"))
]
```

必要なプロダクトを追加する。読み込みと検証だけなら `AgentSkills` 単体で足りる。残り 3 つは
エージェントループから呼べるツールへ積み上げていく:

```swift
.product(name: "AgentSkillsDiscovery", package: "swift-agent-skills"),
.product(name: "AgentSkillsRuntime",   package: "swift-agent-skills"),
.product(name: "AgentSkillsTool",      package: "swift-agent-skills"),
```

## 要件

- iOS 17.0+ / macOS 14.0+ / Linux
- Swift 6.2+

## ライセンス

Apache License 2.0 — [LICENSE](LICENSE) を参照。
