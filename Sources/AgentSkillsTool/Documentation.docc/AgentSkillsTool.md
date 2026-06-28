# ``AgentSkillsTool``

`swift-llm-client` の `Tool` プロトコルに準拠した `invoke_skill` ツール — LLM スタックとスキルシステムをつなぐ唯一の接合点。

## Overview

`AgentSkillsTool` はパッケージの中で唯一 `swift-llm-client` に依存するモジュールです。
エージェントループに登録する `invoke_skill` ツール（`InvokeSkillTool`）を 1 つ提供します。

このツールは構造上、Tier-1 カタログ（`<available_skills>` ブロック）と
Tier-2 有効化（`name` パラメータの列挙）を**同一のスキルスナップショットから生成**します。
モデルがカタログで見えるスキルと、ツールで呼び出せるスキルが必ず一致します。

カタログは `Tool.systemInstruction` に乗ってループが自動的にシステムプロンプトへ注入するため、
呼び出し側は `InvokeSkillTool.make(skills:activator:)` の戻り値をツールリストに追加するだけです。

### エージェントループへの組み込み

```swift
import AgentSkillsTool
import AgentSkillsRuntime
import AgentSkillsDiscovery

// 1. スキルをロードする
let registry = SkillRegistry(discovery: discovery)
await registry.load()
let skills = await registry.available()

// 2. ツールを生成する（スキルがなければ nil）
let activator = SkillActivator(registry: registry)
guard let tool = InvokeSkillTool.make(skills: skills, activator: activator) else {
    // スキルが 0 件 — ツール未登録
    return
}

// 3. エージェントループのツールリストに追加する
// tool.systemInstruction にカタログが含まれており、
// ループが自動的にシステムプロンプトへ注入する。
var tools: [any Tool] = [tool]
```

## Topics

### ツール

- ``InvokeSkillTool``
