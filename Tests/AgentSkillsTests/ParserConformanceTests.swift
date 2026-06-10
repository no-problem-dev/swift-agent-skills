import Testing
import Foundation
import StructuredDataCore
import PersistenceTesting
@testable import AgentSkills

/// Ports `skills-ref/tests/test_parser.py` (16 cases) for byte-level parity.
@Suite("Parser conformance (skills-ref test_parser.py)")
struct ParserConformanceTests {

    private func fs(_ build: (InMemoryFileSystem) async -> Void) async -> InMemoryFileSystem {
        let fs = InMemoryFileSystem()
        await build(fs)
        return fs
    }
    private func dir(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    // MARK: parse_frontmatter

    @Test("valid frontmatter")
    func validFrontmatter() throws {
        let (meta, body) = try SkillFrontmatter.parseFrontmatter("""
        ---
        name: my-skill
        description: A test skill
        ---
        # My Skill

        Instructions here.
        """)
        #expect(meta["name"]?.string == "my-skill")
        #expect(meta["description"]?.string == "A test skill")
        #expect(body.contains("# My Skill"))
    }

    @Test("missing frontmatter")
    func missingFrontmatter() {
        #expect(throws: SkillParseError.self) {
            try SkillFrontmatter.parseFrontmatter("# No frontmatter here")
        }
        #expect {
            try SkillFrontmatter.parseFrontmatter("# No frontmatter here")
        } throws: { ($0 as? SkillParseError)?.message.contains("must start with YAML frontmatter") == true }
    }

    @Test("unclosed frontmatter")
    func unclosedFrontmatter() {
        #expect {
            try SkillFrontmatter.parseFrontmatter("""
            ---
            name: my-skill
            description: A test skill
            """)
        } throws: { ($0 as? SkillParseError)?.message.contains("not properly closed") == true }
    }

    @Test("invalid YAML")
    func invalidYAML() {
        #expect {
            try SkillFrontmatter.parseFrontmatter("""
            ---
            name: [invalid
            description: broken
            ---
            Body here
            """)
        } throws: { ($0 as? SkillParseError)?.message.contains("Invalid YAML") == true }
    }

    @Test("non-dict frontmatter")
    func nonDictFrontmatter() {
        #expect {
            try SkillFrontmatter.parseFrontmatter("""
            ---
            - just
            - a
            - list
            ---
            Body
            """)
        } throws: { ($0 as? SkillParseError)?.message.contains("must be a YAML mapping") == true }
    }

    // MARK: read_properties

    @Test("read valid skill")
    func readValidSkill() async throws {
        let fs = await fs { await $0.addFile(dir("my-skill").appendingPathComponent("SKILL.md"), string: """
        ---
        name: my-skill
        description: A test skill
        license: MIT
        ---
        # My Skill
        """) }
        let props = try await SkillFrontmatter.readProperties(from: dir("my-skill"), fileSystem: fs)
        #expect(props.name == "my-skill")
        #expect(props.description == "A test skill")
        #expect(props.license == "MIT")
    }

    @Test("read with metadata (values stringified)")
    func readWithMetadata() async throws {
        let fs = await fs { await $0.addFile(dir("my-skill").appendingPathComponent("SKILL.md"), string: """
        ---
        name: my-skill
        description: A test skill
        metadata:
          author: Test Author
          version: 1.0
        ---
        Body
        """) }
        let props = try await SkillFrontmatter.readProperties(from: dir("my-skill"), fileSystem: fs)
        #expect(props.metadata == ["author": "Test Author", "version": "1.0"])
    }

    @Test("missing SKILL.md")
    func missingSkillMD() async {
        let fs = InMemoryFileSystem()
        await fs.addDirectory(dir("empty"))
        await #expect {
            try await SkillFrontmatter.readProperties(from: dir("empty"), fileSystem: fs)
        } throws: { ($0 as? SkillParseError)?.message.contains("SKILL.md not found") == true }
    }

    @Test("missing name")
    func missingName() async {
        let fs = await fs { await $0.addFile(dir("my-skill").appendingPathComponent("SKILL.md"), string: """
        ---
        description: A test skill
        ---
        Body
        """) }
        await #expect {
            try await SkillFrontmatter.readProperties(from: dir("my-skill"), fileSystem: fs)
        } throws: { err in
            guard let e = err as? SkillValidationError else { return false }
            return e.message.contains("Missing required field") && e.message.contains("name")
        }
    }

    @Test("missing description")
    func missingDescription() async {
        let fs = await fs { await $0.addFile(dir("my-skill").appendingPathComponent("SKILL.md"), string: """
        ---
        name: my-skill
        ---
        Body
        """) }
        await #expect {
            try await SkillFrontmatter.readProperties(from: dir("my-skill"), fileSystem: fs)
        } throws: { err in
            guard let e = err as? SkillValidationError else { return false }
            return e.message.contains("Missing required field") && e.message.contains("description")
        }
    }

    // MARK: find_skill_md

    @Test("find prefers uppercase SKILL.md")
    func findPrefersUppercase() async {
        let fs = InMemoryFileSystem()
        await fs.addFile(dir("my-skill").appendingPathComponent("SKILL.md"), string: "uppercase")
        await fs.addFile(dir("my-skill").appendingPathComponent("skill.md"), string: "lowercase")
        let found = await SkillFrontmatter.findSkillMD(in: dir("my-skill"), fileSystem: fs)
        #expect(found?.lastPathComponent == "SKILL.md")
    }

    @Test("find accepts lowercase skill.md")
    func findAcceptsLowercase() async {
        let fs = InMemoryFileSystem()
        await fs.addFile(dir("my-skill").appendingPathComponent("skill.md"), string: "lowercase")
        let found = await SkillFrontmatter.findSkillMD(in: dir("my-skill"), fileSystem: fs)
        #expect(found?.lastPathComponent.lowercased() == "skill.md")
    }

    @Test("find returns nil when missing")
    func findReturnsNil() async {
        let fs = InMemoryFileSystem()
        await fs.addDirectory(dir("my-skill"))
        let found = await SkillFrontmatter.findSkillMD(in: dir("my-skill"), fileSystem: fs)
        #expect(found == nil)
    }

    @Test("read properties with lowercase skill.md")
    func readLowercase() async throws {
        let fs = InMemoryFileSystem()
        await fs.addFile(dir("my-skill").appendingPathComponent("skill.md"), string: """
        ---
        name: my-skill
        description: A test skill
        ---
        # My Skill
        """)
        let props = try await SkillFrontmatter.readProperties(from: dir("my-skill"), fileSystem: fs)
        #expect(props.name == "my-skill")
        #expect(props.description == "A test skill")
    }

    @Test("read with allowed-tools (kept as string)")
    func readAllowedTools() async throws {
        let fs = await fs { await $0.addFile(dir("my-skill").appendingPathComponent("SKILL.md"), string: """
        ---
        name: my-skill
        description: A test skill
        allowed-tools: Bash(jq:*) Bash(git:*)
        ---
        Body
        """) }
        let props = try await SkillFrontmatter.readProperties(from: dir("my-skill"), fileSystem: fs)
        #expect(props.allowedTools == "Bash(jq:*) Bash(git:*)")
    }
}
