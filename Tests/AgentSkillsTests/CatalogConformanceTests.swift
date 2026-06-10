import Testing
import Foundation
import PersistenceTesting
@testable import AgentSkills

/// Ports `skills-ref/tests/test_prompt.py` (4 cases) for byte-level parity.
@Suite("Catalog conformance (skills-ref test_prompt.py)")
struct CatalogConformanceTests {

    private let root = URL(fileURLWithPath: "/tmp/catalog")

    private func write(_ fs: InMemoryFileSystem, _ name: String, _ skillMD: String) async -> URL {
        let dir = root.appendingPathComponent(name)
        await fs.addFile(dir.appendingPathComponent("SKILL.md"), string: skillMD)
        return dir
    }

    @Test("empty list")
    func emptyList() async throws {
        let result = try await SkillCatalog.toPrompt(skillDirectories: [], fileSystem: InMemoryFileSystem())
        #expect(result == "<available_skills>\n</available_skills>")
    }

    @Test("single skill")
    func singleSkill() async throws {
        let fs = InMemoryFileSystem()
        let dir = await write(fs, "my-skill", """
        ---
        name: my-skill
        description: A test skill
        ---
        Body
        """)
        let result = try await SkillCatalog.toPrompt(skillDirectories: [dir], fileSystem: fs)
        #expect(result.contains("<available_skills>"))
        #expect(result.contains("</available_skills>"))
        #expect(result.contains("<name>\nmy-skill\n</name>"))
        #expect(result.contains("<description>\nA test skill\n</description>"))
        #expect(result.contains("<location>"))
        #expect(result.contains("SKILL.md"))
    }

    @Test("multiple skills")
    func multipleSkills() async throws {
        let fs = InMemoryFileSystem()
        let a = await write(fs, "skill-a", "---\nname: skill-a\ndescription: First skill\n---\nBody")
        let b = await write(fs, "skill-b", "---\nname: skill-b\ndescription: Second skill\n---\nBody")
        let result = try await SkillCatalog.toPrompt(skillDirectories: [a, b], fileSystem: fs)
        #expect(result.components(separatedBy: "<skill>").count - 1 == 2)
        #expect(result.components(separatedBy: "</skill>").count - 1 == 2)
        #expect(result.contains("skill-a"))
        #expect(result.contains("skill-b"))
    }

    @Test("special characters escaped")
    func specialCharactersEscaped() async throws {
        let fs = InMemoryFileSystem()
        let dir = await write(fs, "special-skill", """
        ---
        name: special-skill
        description: Use <foo> & <bar> tags
        ---
        Body
        """)
        let result = try await SkillCatalog.toPrompt(skillDirectories: [dir], fileSystem: fs)
        #expect(result.contains("&lt;foo&gt;"))
        #expect(result.contains("&amp;"))
        #expect(result.contains("&lt;bar&gt;"))
        #expect(!result.contains("<foo>"))
        #expect(!result.contains("<bar>"))
    }
}
