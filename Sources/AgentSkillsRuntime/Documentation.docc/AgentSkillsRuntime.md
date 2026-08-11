# ``AgentSkillsRuntime``

Advertise skills to a model and turn a chosen one into text for the conversation.

## Overview

`AgentSkillsRuntime` covers the two moments a skill touches an agent loop: listing what is available in the system prompt, and expanding one skill's instructions when the model asks for it.

It depends on no LLM library. A host using something other than `swift-llm-client` can drive it directly; the `Tool` adapter is isolated in `AgentSkillsTool`.

### Listing what is available

``SkillCatalogRenderer`` turns loaded skills into the `<available_skills>` block.

```swift
import AgentSkillsRuntime

let renderer = SkillCatalogRenderer()
if let catalog = renderer.render(skills) {
    let instruction = renderer.instructions(toolName: "invoke_skill")
    systemPrompt += instruction + "\n" + catalog
}
```

``SkillCatalogRenderer/render(_:)`` returns `nil` for an empty list so the section can be dropped from the prompt rather than shown empty.

By default the block leaves out each skill's file path. Giving the model a path invites it to read the skill file directly and skip the activation tool, which loses the loop's only chance to see and control what was loaded. `AgentSkills.SkillCatalog` is the specification-shaped variant that does include paths.

### Activating one

``SkillActivator`` resolves the name, renders the body, wraps it in `<skill_content>` with the skill's base directory and a list of its bundled files, and records the activation.

```swift
let activator = SkillActivator(
    registry: registry,
    renderer: PlainSkillRenderer(),
    session: session          // one instance per conversation
)

switch try await activator.activate(name: modelSuppliedName) {
case .activated(let content, let alreadyActive):
    if !alreadyActive { injectIntoContext(content) }
case .unknown(let available):
    respond("No such skill. Available: \(available.joined(separator: ", "))")
case .notModelInvocable(let name):
    respond("\(name) is trigger-only.")
}
```

Re-activating a skill is not an error and not blocked: the content comes back again with `alreadyActive` set to `true`, and the caller decides whether to inject it a second time. The de-duplication only works if ``SkillSessionState`` is shared across the conversation — a fresh instance per turn makes every activation look like the first.

``SkillActivationOutcome/notModelInvocable(name:)`` is distinct from ``SkillActivationOutcome/unknown(available:)`` on purpose. A skill hidden by a `SkillPolicy` still resolves in the registry, so the model is told it may not call this one rather than being sent off to guess a different name.

### Rendering, and why the default runs nothing

``SkillBodyRenderer`` is the seam where a skill's markdown becomes injectable text. The default, ``PlainSkillRenderer``, returns the body unchanged.

A renderer that executes inline `` !`cmd` `` blocks is the largest attack surface in this flow, because skill content is untrusted input that arrives from a directory the user may not have written. This package ships no such renderer and never makes one the default; a host that wants it writes it and opts in.

### Executing

``SkillExecutor`` decides what happens to the rendered content. ``InlineSkillExecutor``, the only one here, hands it back for injection into the current conversation. Running a skill in a sub-agent — "fork" — is a client-specific pattern outside the standard, so it is left to the consumer to implement.

## Topics

### Advertising skills

- ``SkillCatalogRenderer``

### Activating a skill

- ``SkillActivator``
- ``SkillActivationOutcome``
- ``SkillSessionState``

### Rendering the body

- ``SkillBodyRenderer``
- ``PlainSkillRenderer``

### Executing the result

- ``SkillExecutor``
- ``SkillExecutionResult``
- ``InlineSkillExecutor``
