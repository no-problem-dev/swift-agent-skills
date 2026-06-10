import Testing
import Foundation
import LLMTool
import PersistenceTesting
import AgentSkills
import AgentSkillsDiscovery
import AgentSkillsRuntime
@testable import AgentSkillsTool

/// Exercises the exact end-to-end sequence a host (e.g. A2AResearchDemo's
/// `AgentFleet`) performs at session start: discover → load registry → render
/// the Tier-1 catalog for the system prompt → build the `invoke_skill` tool →
/// the model activates a skill → its body is injected. Verifying it here proves
/// the integration shape independently of the iOS app.
@Suite("Session bootstrap (host integration shape)")
struct SessionBootstrapTests {

    @Test("full loop: discover, catalog, register tool, activate")
    func fullLoop() async throws {
        // 1. A project ships a skill under .agents/skills (cross-client standard).
        let project = URL(fileURLWithPath: "/work/demo")
        let fs = InMemoryFileSystem()
        await fs.addFile(project.appendingPathComponent(".agents/skills/cite-sources/SKILL.md"), string: """
        ---
        name: cite-sources
        description: Attach inline citations to every claim. Use when writing research reports.
        allowed-tools: Read
        ---
        # Cite Sources
        For each claim, append a [n] marker and list the source URL.
        """)

        // 2. Host builds the registry from discovery (secure defaults: trusted project,
        //    PlainSkillRenderer = no command execution).
        let registry = SkillRegistry(discovery: FileSystemSkillDiscovery(
            config: .init(projectRoot: project, worktreeStop: project),
            fileSystem: fs
        ))
        await registry.load()

        // 3. Render the Tier-1 catalog → goes into the worker's system prompt.
        let available = await registry.available()
        let catalog = try #require(SkillCatalogRenderer().render(available))
        #expect(catalog.contains("<name>cite-sources</name>"))
        #expect(!catalog.contains("<location>"))  // location hidden → tool is the only path

        // 4. Build the invoke_skill tool with the name enum bound to the live catalog.
        let session = SkillSessionState()
        let activator = SkillActivator(registry: registry, session: session)
        let tool = try #require(InvokeSkillTool.make(availableNames: available.map(\.name), activator: activator))

        // 5. The model calls invoke_skill(name: "cite-sources").
        let call = try JSONSerialization.data(withJSONObject: ["name": "cite-sources"])
        let result = try await tool.execute(with: call)
        guard case .text(let injected) = result else { Issue.record("expected text result"); return }

        // 6. The wrapped body is what enters the conversation context.
        #expect(injected.contains("<skill_content name=\"cite-sources\">"))
        #expect(injected.contains("append a [n] marker"))
        #expect(await session.wasInvoked("cite-sources"))
    }
}
