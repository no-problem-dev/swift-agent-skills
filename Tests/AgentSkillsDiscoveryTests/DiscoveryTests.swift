import Testing
import Foundation
import PersistenceTesting
@testable import AgentSkillsDiscovery

/// Behavior derived from OpenHands `test_resource_directories.py`,
/// `test_skill_md_convention.py`, `test_load_project_skills.py`, and the
/// official client-implementation guide (lenient warn-and-load, precedence).
@Suite("FileSystem skill discovery")
struct DiscoveryTests {

    private let home = URL(fileURLWithPath: "/home/user")
    private let project = URL(fileURLWithPath: "/work/project")

    private func skillMD(_ name: String, _ desc: String = "A skill") -> String {
        "---\nname: \(name)\ndescription: \(desc)\n---\n# \(name)\nBody for \(name)."
    }

    private func discover(_ fs: InMemoryFileSystem, config: SkillDiscoveryConfig) async -> DiscoveredSkills {
        await FileSystemSkillDiscovery(config: config, fileSystem: fs).discover()
    }

    @Test("discovers SKILL.md under .agents/skills")
    func discoversAgentsDir() async {
        let fs = InMemoryFileSystem()
        await fs.addFile(home.appendingPathComponent(".agents/skills/pdf/SKILL.md"), string: skillMD("pdf", "Handle PDFs"))
        let result = await discover(fs, config: .init(homeDirectory: home))
        #expect(result.skills.map(\.name) == ["pdf"])
        #expect(result.skills[0].description == "Handle PDFs")
        #expect(result.skills[0].body.contains("Body for pdf."))
    }

    @Test("discovers resource directories (scripts/references/assets)")
    func discoversResources() async {
        let fs = InMemoryFileSystem()
        let base = home.appendingPathComponent(".agents/skills/my-skill")
        await fs.addFile(base.appendingPathComponent("SKILL.md"), string: skillMD("my-skill"))
        await fs.addFile(base.appendingPathComponent("scripts/run.sh"), string: "#!/bin/bash")
        await fs.addFile(base.appendingPathComponent("scripts/utils/helper.py"), string: "# helper")
        await fs.addFile(base.appendingPathComponent("references/guide.md"), string: "# Guide")

        let result = await discover(fs, config: .init(homeDirectory: home))
        let resources = try? #require(result.skills.first?.resources)
        #expect(resources?.scripts.sorted() == ["run.sh", "utils/helper.py"])
        #expect(resources?.references == ["guide.md"])
        #expect(resources?.assets == [])
    }

    @Test("lenient: name mismatch loads with a warning")
    func lenientNameMismatch() async {
        let fs = InMemoryFileSystem()
        await fs.addFile(home.appendingPathComponent(".agents/skills/wrong-dir/SKILL.md"),
                         string: skillMD("real-name"))
        let result = await discover(fs, config: .init(homeDirectory: home))
        #expect(result.skills.map(\.name) == ["real-name"])  // loaded anyway
        #expect(result.diagnostics.contains { $0.severity == .warning && $0.message.contains("must match skill name") })
    }

    @Test("lenient: missing description skips the skill")
    func lenientMissingDescription() async {
        let fs = InMemoryFileSystem()
        await fs.addFile(home.appendingPathComponent(".agents/skills/broken/SKILL.md"),
                         string: "---\nname: broken\n---\nBody")
        let result = await discover(fs, config: .init(homeDirectory: home))
        #expect(result.skills.isEmpty)
        #expect(result.diagnostics.contains { $0.severity == .error && $0.message.contains("description") })
    }

    @Test("precedence: project overrides user for same name")
    func projectOverridesUser() async {
        let fs = InMemoryFileSystem()
        await fs.addFile(home.appendingPathComponent(".agents/skills/review/SKILL.md"),
                         string: skillMD("review", "USER version"))
        await fs.addFile(project.appendingPathComponent(".agents/skills/review/SKILL.md"),
                         string: skillMD("review", "PROJECT version"))
        let result = await discover(fs, config: .init(projectRoot: project, worktreeStop: project, homeDirectory: home))
        #expect(result.skills.count == 1)
        #expect(result.skills[0].description == "PROJECT version")
        #expect(result.diagnostics.contains { $0.message.contains("Duplicate skill name 'review'") })
    }

    @Test("trust gate: untrusted project root is skipped")
    func trustGate() async {
        let fs = InMemoryFileSystem()
        await fs.addFile(project.appendingPathComponent(".agents/skills/evil/SKILL.md"), string: skillMD("evil"))
        let result = await discover(fs, config: .init(
            projectRoot: project, worktreeStop: project, isTrusted: { _ in false }
        ))
        #expect(result.skills.isEmpty)
    }

    @Test("registry: disk overrides builtin of same name")
    func registryOverride() async {
        let fs = InMemoryFileSystem()
        await fs.addFile(home.appendingPathComponent(".agents/skills/greet/SKILL.md"),
                         string: skillMD("greet", "DISK greet"))
        let builtin = LoadedSkill(
            name: "greet", description: "BUILTIN greet", body: "builtin body",
            location: .builtin(name: "greet"),
            properties: .init(name: "greet", description: "BUILTIN greet")
        )
        let registry = SkillRegistry(
            builtins: [builtin],
            discovery: FileSystemSkillDiscovery(config: .init(homeDirectory: home), fileSystem: fs)
        )
        await registry.load()
        #expect(await registry.get("greet")?.description == "DISK greet")
    }
}
