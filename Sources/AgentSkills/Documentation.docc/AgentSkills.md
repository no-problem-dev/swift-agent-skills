# ``AgentSkills``

Parse, validate, serialize and catalog `SKILL.md` files — the pure core of the SKILL.md open standard in Swift.

> **Unofficial.** This project has no connection to the authors of the Agent Skills standard and is not endorsed by them. Conforming to the specification is not a goal of this project.

## Overview

`AgentSkills` is a Swift port of the [Agent Skills standard](https://agentskills.io). It reads and writes `SKILL.md` frontmatter, checks it against the standard's rules, and builds the `<available_skills>` catalog that goes into an agent's system prompt.

Nothing in this module reaches for a filesystem on its own. Directory-based entry points take a `FileSystemReading` backend, so a test can run the same code against an in-memory tree, and a sandboxed host can supply its own reader.

This module is strict: a malformed `SKILL.md` throws. That is the right behavior for an authoring tool and the wrong one for loading whatever a user happens to have on disk, which is why `AgentSkillsDiscovery` re-implements loading leniently instead of reusing ``SkillFrontmatter`` as a gate.

### The four libraries

`AgentSkills` is the foundation the other three build on.

- **`AgentSkillsDiscovery`** scans a filesystem for skills and loads them leniently, holds them in a registry, and writes new ones back out.
- **`AgentSkillsRuntime`** renders the catalog for the system prompt and activates a skill on request. Like this module, it depends on no LLM library.
- **`AgentSkillsTool`** is the only module that depends on `swift-llm-client`. It supplies `InvokeSkillTool`, which derives the catalog and the callable skill names from a single snapshot.

### Reading a skill

```swift
import AgentSkills

let content = """
---
name: my-skill
description: Does the thing. Use when a draft needs checking.
---
The markdown body of the skill.
"""

let (frontmatter, body) = try SkillFrontmatter.parseFrontmatter(content)
let properties = try SkillProperties(frontmatter: frontmatter)
print(properties.name)   // "my-skill"

// Strict validation is separate: parsing succeeds on skills validation rejects.
let errors = SkillValidator.validate(frontmatter: frontmatter, directoryName: "my-skill")
assert(errors.isEmpty)

// Write it back out. Field order is canonical, so the bytes are stable.
let serialized = SkillDocument.serialize(properties: properties, body: body)
```

### Two things that bite

The closing `---` fence is found by scanning for the next `---` anywhere in the text, quoting included. A frontmatter value containing `---` therefore closes the block early, and the file fails to parse with a YAML error rather than an obvious one.

Validation reports rather than throws. ``SkillValidator/validate(frontmatter:directoryName:)`` returns an array of messages; an empty array means valid. Code that ignores the return value validates nothing.

## Topics

### Reading a skill

- ``SkillFrontmatter``
- ``SkillProperties``

### Checking it

- ``SkillValidator``

### Writing one back

- ``SkillDocument``

### Advertising skills to a model

- ``SkillCatalog``

### Errors

- ``SkillParseError``
- ``SkillValidationError``
