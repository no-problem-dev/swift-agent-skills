# ``AgentSkillsDiscovery``

Find skills on disk, load them even when they are imperfect, and keep them in a registry.

## Overview

`AgentSkillsDiscovery` scans a filesystem for `SKILL.md` files and loads them leniently: a skill that fails strict validation still loads, and the problems are recorded as diagnostics instead of stopping the scan.

Only two things are fatal to a skill. If its `SKILL.md` cannot be read or parsed, or if it has no description, the skill is dropped and an `.error` diagnostic takes its place — a description is what a model reads to decide whether to activate the skill, so a skill without one cannot be advertised at all. Everything else, including a `name` that disagrees with the directory name, is a warning attached to a skill that loaded anyway.

Filesystem access goes through `FileSystemReading` and `FileSystemWriting` (from `swift-persistence`), so the same scan runs against a real tree in production and an in-memory one in tests.

### Scanning

```swift
import AgentSkillsDiscovery
import PersistenceFileSystem

let config = SkillDiscoveryConfig(
    projectRoot: URL(filePath: "/path/to/project"),
    worktreeStop: URL(filePath: "/path/to/project"),
    homeDirectory: FileManager.default.homeDirectoryForCurrentUser
)
let discovery = FileSystemSkillDiscovery(config: config, fileSystem: FoundationFileSystem())
let result = await discovery.discover()

print(result.skills.map(\.name))
for diagnostic in result.diagnostics where diagnostic.severity == .error {
    print("skipped:", diagnostic.location, diagnostic.message)
}
```

Read the diagnostics. A skill that fails to load leaves no other trace.

### Which skill wins

Roots are visited in one order — user, then project from ``SkillDiscoveryConfig/projectRoot`` upward to ``SkillDiscoveryConfig/worktreeStop``, then ``SkillDiscoveryConfig/extraRoots`` — and when two skills share a name the higher ``SkillScope`` wins: explicit beats project beats user. The loser is reported as a warning naming the scope that shadowed it.

Two details of that rule are easy to get wrong:

- Between roots of the **same** scope, the one visited later wins. Since the project walk runs from the project root upward, an ancestor directory's skill shadows the project root's own skill of that name.
- `.claude/skills/` is scanned after `.agents/skills/`, so within one directory the Claude copy shadows the standard one.

A project-scope root is only scanned if ``SkillDiscoveryConfig/isTrusted`` returns `true` for it. User roots and extra roots are not gated — an untrusted tree must be kept out of `extraRoots` by the caller.

### Registry

``SkillRegistry`` seeds builtins and then lets discovered skills overwrite them by name, so a user can replace a builtin by shipping one with the same name.

```swift
let registry = SkillRegistry(builtins: builtins, discovery: discovery)
await registry.load()                       // required; nothing is loaded until this runs
let skill = await registry.get("my-skill")
let visible = await registry.available()    // policy-filtered, for the model
```

Nothing is cached between calls and nothing watches the filesystem. The registry holds the snapshot from the last ``SkillRegistry/load()`` and only re-reads when you call it again, so a host that lets users edit skills has to reload after an edit.

### Authoring

``SkillWriter`` validates before it writes, so a skill it creates is one discovery loads without warnings. Renaming moves the directory, keeping bundled `scripts/`, `references/` and `assets/` files with the skill.

```swift
let writer = SkillWriter(root: skillsRoot, fileSystem: FoundationFileSystem())
try await writer.create(
    properties: SkillProperties(name: "new-skill", description: "Does the thing."),
    body: "# Instructions\n..."
)
```

Only ``SkillProperties/name`` is validated. ``SkillWriter/delete(name:)`` and the `originalName` argument of ``SkillWriter/update(originalName:properties:body:)`` are joined to the root exactly as given, so neither should ever receive unchecked input.

## Topics

### Scanning

- ``SkillDiscovering``
- ``FileSystemSkillDiscovery``
- ``SkillDiscoveryConfig``
- ``SkillScope``

### What a scan returns

- ``DiscoveredSkills``
- ``LoadedSkill``
- ``SkillLocation``
- ``SkillResources``
- ``SkillDiagnostic``

### Holding skills in memory

- ``SkillRegistry``
- ``SkillPolicy``

### Authoring skills

- ``SkillWriter``
- ``SkillWriteError``
