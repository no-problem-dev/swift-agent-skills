import Testing
import Foundation
import PersistenceTesting
import AgentSkills
@testable import AgentSkillsDiscovery

/// Authoring side — the write mirror of discovery. Uses the in-memory filesystem
/// (read + write) so disk is never touched.
@Suite("SkillWriter")
struct SkillWriterTests {

    private let root = URL(fileURLWithPath: "/home/user/.agents/skills")

    private func writer(_ fs: InMemoryFileSystem) -> SkillWriter<InMemoryFileSystem> {
        SkillWriter(root: root, fileSystem: fs)
    }

    private func props(_ name: String, _ description: String = "A useful skill.") -> SkillProperties {
        SkillProperties(name: name, description: description)
    }

    @Test("create writes a discoverable SKILL.md")
    func create() async throws {
        let fs = InMemoryFileSystem()
        try await writer(fs).create(properties: props("deep-research"), body: "# Body")

        let manifest = root.appendingPathComponent("deep-research/SKILL.md")
        #expect(await fs.exists(manifest))

        // Round-trips through discovery.
        let discovery = FileSystemSkillDiscovery(
            config: .init(homeDirectory: URL(fileURLWithPath: "/home/user")),
            fileSystem: fs
        )
        let discovered = await discovery.discover()
        #expect(discovered.skills.map(\.name) == ["deep-research"])
        #expect(discovered.diagnostics.isEmpty)
    }

    @Test("create rejects invalid properties before writing")
    func createRejectsInvalid() async throws {
        let fs = InMemoryFileSystem()
        await #expect(throws: SkillWriteError.self) {
            try await writer(fs).create(properties: props("Has Spaces"), body: "x")
        }
        #expect(await fs.exists(root.appendingPathComponent("Has Spaces/SKILL.md")) == false)
    }

    @Test("create throws on name collision")
    func createCollision() async throws {
        let fs = InMemoryFileSystem()
        try await writer(fs).create(properties: props("dup"), body: "a")
        await #expect(throws: SkillWriteError.self) {
            try await writer(fs).create(properties: props("dup"), body: "b")
        }
    }

    @Test("update in place overwrites the manifest")
    func updateInPlace() async throws {
        let fs = InMemoryFileSystem()
        let w = writer(fs)
        try await w.create(properties: props("x", "Old description."), body: "old")
        try await w.update(originalName: "x", properties: props("x", "New description."), body: "new")

        let content = try await fs.readString(root.appendingPathComponent("x/SKILL.md"))
        #expect(content.contains("New description."))
        #expect(content.contains("new"))
    }

    @Test("update with rename moves the directory, preserving resources")
    func updateRenamePreservesResources() async throws {
        let fs = InMemoryFileSystem()
        let w = writer(fs)
        try await w.create(properties: props("old-name"), body: "body")
        // A resource file alongside the manifest must survive the rename.
        try await fs.write("#!/bin/bash", to: root.appendingPathComponent("old-name/scripts/run.sh"))

        try await w.update(originalName: "old-name", properties: props("new-name"), body: "body")

        #expect(await fs.exists(root.appendingPathComponent("old-name")) == false)
        #expect(await fs.exists(root.appendingPathComponent("new-name/SKILL.md")))
        #expect(try await fs.readString(root.appendingPathComponent("new-name/scripts/run.sh")) == "#!/bin/bash")
    }

    @Test("update rename throws when the target name is taken")
    func updateRenameCollision() async throws {
        let fs = InMemoryFileSystem()
        let w = writer(fs)
        try await w.create(properties: props("a"), body: "a")
        try await w.create(properties: props("b"), body: "b")
        await #expect(throws: SkillWriteError.self) {
            try await w.update(originalName: "a", properties: props("b"), body: "a")
        }
    }

    @Test("delete removes the skill and is a no-op when absent")
    func delete() async throws {
        let fs = InMemoryFileSystem()
        let w = writer(fs)
        try await w.create(properties: props("gone"), body: "x")
        try await w.delete(name: "gone")
        #expect(await fs.exists(root.appendingPathComponent("gone")) == false)
        try await w.delete(name: "gone") // no throw
    }
}
