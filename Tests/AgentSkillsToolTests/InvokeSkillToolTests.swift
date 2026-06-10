import Testing
import Foundation
import PersistenceTesting
import AgentSkillsDiscovery
import AgentSkillsRuntime
@testable import AgentSkillsTool

@Suite("invoke_skill Tool adapter")
struct InvokeSkillToolTests {

    private let home = URL(fileURLWithPath: "/home/user")

    private func registry(_ names: [String]) async -> SkillRegistry {
        let fs = InMemoryFileSystem()
        for name in names {
            await fs.addFile(home.appendingPathComponent(".agents/skills/\(name)/SKILL.md"),
                             string: "---\nname: \(name)\ndescription: The \(name) skill\n---\n# \(name)\nBody \(name).")
        }
        let reg = SkillRegistry(discovery: FileSystemSkillDiscovery(config: .init(homeDirectory: home), fileSystem: fs))
        await reg.load()
        return reg
    }

    @Test("tool exposes name enum constrained to available skills")
    func enumConstrained() async {
        let reg = await registry(["pdf", "review"])
        let tool = InvokeSkillTool.make(
            availableNames: await reg.available().map(\.name),
            activator: SkillActivator(registry: reg)
        )
        let tool2 = try! #require(tool)
        #expect(tool2.toolName == "invoke_skill")
        #expect(tool2.inputSchema.properties?["name"]?.enum == ["pdf", "review"])
    }

    @Test("no skills → no tool registered")
    func noSkillsNoTool() async {
        let reg = await registry([])
        let tool = InvokeSkillTool.make(availableNames: await reg.available().map(\.name),
                                        activator: SkillActivator(registry: reg))
        #expect(tool == nil)
    }

    @Test("executing the tool returns wrapped skill content")
    func executeReturnsContent() async throws {
        let reg = await registry(["pdf"])
        let tool = InvokeSkillTool.make(availableNames: await reg.available().map(\.name),
                                        activator: SkillActivator(registry: reg))!
        let args = try JSONSerialization.data(withJSONObject: ["name": "pdf"])
        let result = try await tool.execute(with: args)
        guard case .text(let text) = result else { Issue.record("expected text"); return }
        #expect(text.contains("<skill_content name=\"pdf\">"))
        #expect(text.contains("Body pdf."))
    }

    @Test("executing with unknown skill returns an error result")
    func executeUnknown() async throws {
        let reg = await registry(["pdf"])
        let tool = InvokeSkillTool.make(availableNames: ["pdf", "ghost"],
                                        activator: SkillActivator(registry: reg))!
        let args = try JSONSerialization.data(withJSONObject: ["name": "ghost"])
        let result = try await tool.execute(with: args)
        guard case .error(let message) = result else { Issue.record("expected error"); return }
        #expect(message.contains("Unknown skill 'ghost'"))
    }
}
