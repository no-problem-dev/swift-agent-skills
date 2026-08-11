# swift-agent-skills

English | [日本語](./README.ja.md)

Give an agent a folder of written procedures and let it load only the one it needs, instead of carrying every instruction in its system prompt.

> **Unofficial.** Not affiliated with or endorsed by the authors of the Agent Skills standard. Conforming to the specification is not a goal of this project.

## Overview

A Swift implementation of [Agent Skills](https://agentskills.io) — the open `SKILL.md` format
(originally developed by Anthropic, Apache-2.0, governed at `github.com/agentskills/agentskills`).
A skill is a directory holding instructions and supporting files. The agent sees a short catalog of
what is available and pulls in a skill's full text only when it decides to use one.

- **The prompt stays small** — the model reads one line per skill and asks for the body on demand,
  so twenty skills cost roughly what a table of contents costs
- **Skills are inert text** — loading one puts words in the context window and nothing else. Inline
  `` !`cmd` `` blocks are not executed by the default renderer
- **Untrusted checkouts cannot inject instructions** — project-level skill roots pass a trust gate
  first, so cloning a repository does not hand it your agent's prompt
- **Supporting files are listed, not read** — scripts and references show up as paths the model can
  request, so a large skill directory does not arrive all at once
- **Found where authors already put them** — `.agents/skills` plus `.claude/skills`, walking up from
  the project directory, with project skills overriding user-level ones of the same name
- **The filesystem is injectable** — real disk in production, in-memory in tests, same code path

## Quick Start

Discover the skills on disk and expose them to a loop as one tool:

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
    tools.append(skillTool)   // carries the catalog on Tool.systemInstruction
}
```

## Documentation

[**AgentSkills**](https://no-problem-dev.github.io/swift-agent-skills/documentation/agentskills/) — parsing, validation and serialization ·
[**AgentSkillsDiscovery**](https://no-problem-dev.github.io/swift-agent-skills/documentation/agentskillsdiscovery/) — search roots, precedence and the trust gate ·
[**AgentSkillsRuntime**](https://no-problem-dev.github.io/swift-agent-skills/documentation/agentskillsruntime/) — catalog rendering and activation ·
[**AgentSkillsTool**](https://no-problem-dev.github.io/swift-agent-skills/documentation/agentskillstool/) — the `invoke_skill` tool adapter

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-agent-skills.git", .upToNextMinor(from: "0.4.0"))
]
```

Add the products you need. `AgentSkills` alone is enough to read and validate documents; the other
three build up to a tool an agent loop can call:

```swift
.product(name: "AgentSkillsDiscovery", package: "swift-agent-skills"),
.product(name: "AgentSkillsRuntime",   package: "swift-agent-skills"),
.product(name: "AgentSkillsTool",      package: "swift-agent-skills"),
```

## Requirements

- iOS 17.0+ / macOS 14.0+ / Linux
- Swift 6.2+

## License

Apache License 2.0 — see [LICENSE](LICENSE).
