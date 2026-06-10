import Testing
import Foundation
import PersistenceTesting
import AgentSkills
import AgentSkillsDiscovery
@testable import AgentSkillsRuntime

/// Loop activation behavior derived from OpenHands `invoke_skill` and the
/// official client guide (catalog hides location, `<skill_content>` wrap,
/// resource footer, dedupe).
@Suite("Skill activation runtime")
struct RuntimeTests {

    private let home = URL(fileURLWithPath: "/home/user")

    private func skillMD(_ name: String, _ desc: String) -> String {
        "---\nname: \(name)\ndescription: \(desc)\n---\n# \(name)\nDo the \(name) thing."
    }

    private func registry(_ build: (InMemoryFileSystem) async -> Void) async -> SkillRegistry {
        let fs = InMemoryFileSystem()
        await build(fs)
        let reg = SkillRegistry(discovery: FileSystemSkillDiscovery(
            config: .init(homeDirectory: home), fileSystem: fs))
        await reg.load()
        return reg
    }

    // MARK: Catalog (Tier 1)

    @Test("catalog hides location by default and lists name+description")
    func catalogHidesLocation() async {
        let reg = await registry {
            await $0.addFile(home.appendingPathComponent(".agents/skills/pdf/SKILL.md"), string: skillMD("pdf", "Handle PDFs"))
        }
        let catalog = SkillCatalogRenderer().render(await reg.available())
        let text = try! #require(catalog)
        #expect(text.contains("<name>pdf</name>"))
        #expect(text.contains("<description>Handle PDFs</description>"))
        #expect(!text.contains("<location>"))
    }

    @Test("empty catalog renders nil")
    func emptyCatalog() {
        #expect(SkillCatalogRenderer().render([]) == nil)
    }

    @Test("catalog can opt into including location")
    func catalogWithLocation() async {
        let reg = await registry {
            await $0.addFile(home.appendingPathComponent(".agents/skills/pdf/SKILL.md"), string: skillMD("pdf", "Handle PDFs"))
        }
        let text = SkillCatalogRenderer(includeLocation: true).render(await reg.available())!
        #expect(text.contains("<location>"))
        #expect(text.contains("SKILL.md"))
    }

    // MARK: Activation (Tier 2)

    @Test("activation wraps body in <skill_content> with base-dir footer")
    func activationWraps() async throws {
        let reg = await registry {
            await $0.addFile(home.appendingPathComponent(".agents/skills/pdf/SKILL.md"), string: skillMD("pdf", "Handle PDFs"))
        }
        let activator = SkillActivator(registry: reg)
        let outcome = try await activator.activate(name: "pdf")
        guard case .activated(let content, let already) = outcome else {
            Issue.record("expected activated"); return
        }
        #expect(content.hasPrefix("<skill_content name=\"pdf\">"))
        #expect(content.contains("Do the pdf thing."))
        #expect(content.contains("Base directory for this skill:"))
        #expect(content.hasSuffix("</skill_content>"))
        #expect(already == false)
    }

    @Test("activation lists bundled resources without reading them")
    func activationListsResources() async throws {
        let reg = await registry {
            let base = home.appendingPathComponent(".agents/skills/pdf")
            await $0.addFile(base.appendingPathComponent("SKILL.md"), string: skillMD("pdf", "Handle PDFs"))
            await $0.addFile(base.appendingPathComponent("scripts/extract.py"), string: "print('x')")
        }
        let outcome = try await SkillActivator(registry: reg).activate(name: "pdf")
        guard case .activated(let content, _) = outcome else { Issue.record("expected activated"); return }
        #expect(content.contains("<skill_files>"))
        #expect(content.contains("<file>extract.py</file>"))
        #expect(!content.contains("print('x')"))  // listed, not read
    }

    @Test("unknown skill returns available names")
    func unknownSkill() async throws {
        let reg = await registry {
            await $0.addFile(home.appendingPathComponent(".agents/skills/pdf/SKILL.md"), string: skillMD("pdf", "Handle PDFs"))
        }
        let outcome = try await SkillActivator(registry: reg).activate(name: "nope")
        #expect(outcome == .unknown(available: ["pdf"]))
    }

    @Test("re-activation reports alreadyActive (dedupe)")
    func dedupe() async throws {
        let reg = await registry {
            await $0.addFile(home.appendingPathComponent(".agents/skills/pdf/SKILL.md"), string: skillMD("pdf", "Handle PDFs"))
        }
        let session = SkillSessionState()
        let activator = SkillActivator(registry: reg, session: session)
        _ = try await activator.activate(name: "pdf")
        let second = try await activator.activate(name: "pdf")
        guard case .activated(_, let already) = second else { Issue.record("expected activated"); return }
        #expect(already == true)
    }

    @Test("policy can hide a skill from activation")
    func policyBlocks() async throws {
        let reg = await registry {
            await $0.addFile(home.appendingPathComponent(".agents/skills/pdf/SKILL.md"), string: skillMD("pdf", "Handle PDFs"))
        }
        let policy = SkillPolicy { $0 != "pdf" }
        let outcome = try await SkillActivator(registry: reg, policy: policy).activate(name: "pdf")
        #expect(outcome == .notModelInvocable(name: "pdf"))
    }
}
