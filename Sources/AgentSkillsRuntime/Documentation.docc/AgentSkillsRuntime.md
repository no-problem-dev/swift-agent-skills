# ``AgentSkillsRuntime``

エージェントループへスキルを有効化・注入する実行層 — LLM 依存を持たないピュアな活性化エンジン。

## Overview

`AgentSkillsRuntime` はエージェントループの Tier-1（カタログ提示）と
Tier-2（スキル有効化）を実装するモジュールです。
LLM スタックへの依存を一切持たないため、単体テストが容易で、
`swift-llm-client` 以外の LLM ライブラリを使う環境にも持ち込めます。

ツールとしての統合（`Tool` プロトコルへの準拠）は `AgentSkillsTool` が担います。

### Tier-1: カタログのレンダリング

`SkillCatalogRenderer` は `[LoadedSkill]` から `<available_skills>` XML ブロックを生成します。
デフォルトでは `<location>` を省略し、モデルがファイルを直接読んでツールをバイパスすることを防ぎます
（OpenHands の動作に準拠）。

```swift
import AgentSkillsRuntime

let renderer = SkillCatalogRenderer()
if let catalog = renderer.render(skills) {
    // システムプロンプトへ注入する
    let instruction = renderer.instructions(toolName: "invoke_skill")
    print(instruction + "\n" + catalog)
}
```

### Tier-2: スキルの有効化

`SkillActivator` はスキル名を解決し、`SkillBodyRenderer` でボディをレンダリングして、
`<skill_content>` ラッパーで包み、`SkillSessionState` に記録します。
同じスキルを重複で有効化しても `alreadyActive: true` を返すだけで二重注入を防ぎます。

```swift
let activator = SkillActivator(
    registry: registry,
    renderer: PlainSkillRenderer(),
    session: SkillSessionState()
)

switch try await activator.activate(name: "my-skill") {
case .activated(let content, let alreadyActive):
    if !alreadyActive { injectIntoContext(content) }
case .unknown(let available):
    print("利用可能なスキル: \(available)")
case .notModelInvocable(let name):
    print("\(name) はトリガー専用スキルです")
}
```

### スキルの実行方法

`SkillExecutor` プロトコルでスキルの実行戦略を差し替えられます。
このパッケージが提供するのは `InlineSkillExecutor`（レンダリング済みコンテンツをそのまま返す）のみです。
サブエージェントで別セッションで実行する「fork」パターンは Agent Skills 標準の任意拡張であり、
コンシューマ側が `SkillExecutor` を実装して注入します。

## Topics

### カタログレンダリング

- ``SkillCatalogRenderer``

### 有効化

- ``SkillActivator``
- ``SkillActivationOutcome``

### ボディレンダリング

- ``SkillBodyRenderer``
- ``PlainSkillRenderer``

### 実行

- ``SkillExecutor``
- ``SkillExecutionResult``
- ``InlineSkillExecutor``

### セッション管理

- ``SkillSessionState``
