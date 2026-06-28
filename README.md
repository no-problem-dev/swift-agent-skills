# swift-agent-skills

English | [日本語](./README.ja.md)

A standards-conformant Swift implementation of [Agent Skills](https://agentskills.io)
(the open `SKILL.md` standard originally developed by Anthropic, Apache-2.0,
governed at `github.com/agentskills/agentskills`).

It is the "load procedural knowledge into one agent" primitive — complementary to
A2A (advertise capabilities across agents) and MCP (connect tools). Skills are
**inert data loaded into context via progressive disclosure**; running a skill in
a subagent ("fork") is an optional, non-standard pattern and is intentionally left
to the consumer (see `SkillExecutor`).

## Target layering

Dependencies flow one way; the LLM coupling is isolated to a single thin target.

| Target | Role | Depends on |
|---|---|---|
| `AgentSkills` | **Strict standard core** — parser / validator / catalog, a 1:1 port of `skills-ref` (`parser.py`/`validator.py`/`prompt.py`). | `StructuredDataCore`, `YAMLParsing`, `PersistenceCore` |
| `AgentSkillsDiscovery` | **Lenient multi-root discovery** (warn-and-load) over an injected filesystem. `.agents/skills` (standard) + `.claude/skills` (compat), parent walk, trust gate, resource enumeration. | `AgentSkills`, `PersistenceCore` |
| `AgentSkillsRuntime` | **Loop activation logic** — catalog renderer (location hidden), `SkillActivator`, dedupe, `SkillBodyRenderer` (Plain default), `SkillExecutor`. No LLM dependency. | `AgentSkillsDiscovery` |
| `AgentSkillsTool` | **`invoke_skill` `Tool` adapter** — the only LLM-coupled surface. | `AgentSkillsRuntime`, `LLMTool` |

The filesystem is abstracted via `swift-persistence` `FileSystemReading`
(`PersistenceCore`), with `FoundationFileSystem` (disk) and `InMemoryFileSystem`
(tests) as swappable implementations.

## Installation (Swift Package Manager)

Add to `dependencies` in `Package.swift`:

```swift
.package(url: "https://github.com/no-problem-dev/swift-agent-skills.git", from: "<version>")
```

Add the required libraries to your target:

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

## Usage

### Host integration (e.g. A2AResearchDemo)

At session start a host discovers skills and registers the tool. The catalog is
carried on `Tool.systemInstruction` — the loop injects it automatically:

```swift
import AgentSkillsDiscovery
import AgentSkillsRuntime
import AgentSkillsTool
import PersistenceFileSystem

// 1. Discover (secure defaults: trusted project, no command execution).
let registry = SkillRegistry(discovery: FileSystemSkillDiscovery(
    config: .init(projectRoot: projectRoot, worktreeStop: repoRoot, homeDirectory: home,
                  isTrusted: { trustStore.isTrusted($0) }),
    fileSystem: FoundationFileSystem()
))
await registry.load()

// 2. Tool → worker tool list. InvokeSkillTool sets Tool.systemInstruction;
//    the loop injects the catalog automatically (no manual systemPrompt mutation needed).
let activator = SkillActivator(registry: registry, session: SkillSessionState())
var tools: [any Tool] = existingWorkerTools
if let skillTool = InvokeSkillTool.make(skills: await registry.available(), activator: activator) {
    tools.append(skillTool)
}
```

In StudioFeature this slots into `WorkerConfiguration.tools` (researcher/host) and
the system-prompt assembly. Fork execution, if wanted for a worker, is provided by
passing a consumer `SkillExecutor` built on `swift-agent-runtime`.

#### Release ordering (prerequisite for the app build)

The app uses versioned (git URL) dependencies, so integration requires, in order:

1. Release `swift-persistence` with the new `FileSystemReading` (this repo depends
   on it).
2. Switch this package's dependencies from `path:` to versioned URLs and tag it.
3. Add `swift-agent-skills` (URL) to `StudioFeature/Package.swift` and wire the
   snippet above; build for iOS in Xcode.

### Core API

Parse, validate, and serialize `SKILL.md` content directly using `AgentSkills`:

```swift
import AgentSkills

// Parse SKILL.md content and access properties.
let content = """
---
name: my-skill
description: Does something.
---
Skill body in Markdown.
"""

let (frontmatter, body) = try SkillFrontmatter.parseFrontmatter(content)
let properties = try SkillProperties(frontmatter: frontmatter)
print(properties.name)   // "my-skill"
print(body)              // "Skill body in Markdown."

// Strict validation.
let errors = SkillValidator.validate(frontmatter: frontmatter, directoryName: "my-skill")
assert(errors.isEmpty)

// Re-serialize the SKILL.md document.
let serialized = SkillDocument.serialize(properties: properties, body: body)
```

## Conformance via official tests (TDD)

- `AgentSkills` is verified against the official `skills-ref` suite ported
  verbatim — `test_parser.py` (16), `test_validator.py` (24/21), `test_prompt.py`
  (4). NFKC + i18n names, the 6 `ALLOWED_FIELDS`, metadata stringification, and
  `SKILL.md`/`skill.md` fallback all match the reference byte-for-byte.
- `AgentSkillsDiscovery` / `AgentSkillsRuntime` behavior is derived from OpenHands
  (`invoke_skill`, resource directories, name-mismatch lenience, precedence) and
  the official client-implementation guide.

## Security posture

- **No command execution by default.** `PlainSkillRenderer` never runs inline
  `` !`cmd` `` blocks; dynamic rendering is a separate opt-in `SkillBodyRenderer`.
- **Trust gate** on project-level roots (`SkillDiscoveryConfig.isTrusted`) so an
  untrusted cloned repo can't silently inject instructions.
- **Resources are listed, never eagerly read** — the model loads them on demand.
- **Catalog hides `<location>`** so the model must go through `invoke_skill`.

## License

Apache License 2.0
