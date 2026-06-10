import Testing
import Foundation
import PersistenceFileSystem
@testable import AgentSkillsDiscovery

/// End-to-end discovery against the real `FoundationFileSystem` on a temp
/// directory — proves the filesystem abstraction works on disk, not just the
/// in-memory double.
@Suite("Discovery over real FoundationFileSystem")
struct RealFileSystemTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentSkillsE2E-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("discovers a real on-disk skill with resources")
    func discoversOnDisk() async throws {
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        let skillDir = home.appendingPathComponent(".agents/skills/deep-research")
        let scripts = skillDir.appendingPathComponent("scripts")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try """
        ---
        name: deep-research
        description: Run a multi-source research sweep and synthesize a cited report.
        license: Apache-2.0
        metadata:
          author: no-problem
          version: "1.0"
        ---
        # Deep Research

        1. Fan out searches. 2. Verify claims. 3. Synthesize with citations.
        """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "print('search')".write(to: scripts.appendingPathComponent("search.py"), atomically: true, encoding: .utf8)

        let discovery = FileSystemSkillDiscovery(
            config: .init(homeDirectory: home),
            fileSystem: FoundationFileSystem()
        )
        let result = await discovery.discover()

        #expect(result.diagnostics.isEmpty)
        #expect(result.skills.count == 1)
        let skill = try #require(result.skills.first)
        #expect(skill.name == "deep-research")
        #expect(skill.properties.license == "Apache-2.0")
        #expect(skill.properties.metadata["version"] == "1.0")
        #expect(skill.resources?.scripts == ["search.py"])
        #expect(skill.body.contains("Fan out searches"))
    }
}
