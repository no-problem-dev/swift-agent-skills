# ``AgentSkillsTool``

The `invoke_skill` tool — the single joint between an LLM tool loop and the skill system.

## Overview

`AgentSkillsTool` is the only module in this package that depends on `swift-llm-client`. It provides one type, ``InvokeSkillTool``, which conforms to the `Tool` protocol.

The tool derives both halves of the contract from a single snapshot of skills: the `<available_skills>` catalog it carries in `systemInstruction`, and the enumeration of names its input schema accepts. The model therefore cannot be shown a skill it is unable to call, or be given a name that was never advertised — the two lists cannot drift because there is only one list.

The catalog rides into the system prompt through `Tool.systemInstruction`, which the loop injects. A caller registers the tool and renders nothing itself.

### Wiring it into a loop

```swift
import AgentSkillsTool
import AgentSkillsRuntime
import AgentSkillsDiscovery

// 1. Load the skills.
let registry = SkillRegistry(discovery: discovery)
await registry.load()
let skills = await registry.available()

// 2. Build the tool. nil when there are no skills to advertise.
let activator = SkillActivator(registry: registry, session: session)
guard let tool = InvokeSkillTool.make(skills: skills, activator: activator) else {
    return   // nothing to register
}

// 3. Register it. tool.systemInstruction carries the catalog; the loop injects it.
var tools: [any Tool] = [tool]
```

### What the model sees when it gets it wrong

``InvokeSkillTool/execute(with:)`` does not throw on bad input. A missing or empty `name`, a name that no longer resolves, and a skill the policy hides all come back as an error `ToolResult` — text the model reads and can correct against, with the unknown-skill case listing the names that would have worked.

### The snapshot is frozen

The skill list is captured when the tool is built. Reloading the registry does not update an already-registered tool, so a host that lets users add or edit skills mid-session has to rebuild the tool and re-register it; otherwise the model keeps being offered the old set.

## Topics

### The tool

- ``InvokeSkillTool``
