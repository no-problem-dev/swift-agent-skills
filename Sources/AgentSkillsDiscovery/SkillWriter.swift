import Foundation
import AgentSkills
import PersistenceCore

/// Errors raised while authoring skills to disk.
public enum SkillWriteError: Error, Equatable {
    /// The properties failed strict validation; carries the validator messages.
    case validationFailed([String])
    /// A skill directory already exists at the target name.
    case nameCollision(String)
    /// The skill to update/delete does not exist.
    case notFound(String)
}

/// Writes user-authored skills under a root directory — the write mirror of
/// ``FileSystemSkillDiscovery``.
///
/// Serializes ``SkillProperties`` with ``SkillDocument`` (strict-validated first)
/// and persists through an injected ``FileSystemWriting`` backend, so authoring
/// is testable in-memory and swappable for sandboxed/remote storage. A skill
/// lives at `<root>/<name>/SKILL.md`; renames move the whole directory so
/// resource files (`scripts/`, `references/`, `assets/`) are preserved.
public struct SkillWriter<FS: FileSystemReading & FileSystemWriting>: Sendable {

    /// The user skills root, e.g. `~/Documents/.agents/skills`.
    public let root: URL
    public let fileSystem: FS

    public init(root: URL, fileSystem: FS) {
        self.root = root
        self.fileSystem = fileSystem
    }

    private func directory(_ name: String) -> URL {
        root.appendingPathComponent(name, isDirectory: true)
    }

    private func manifest(_ name: String) -> URL {
        directory(name).appendingPathComponent("SKILL.md")
    }

    /// Creates a new skill. Validates, then fails if a skill of that name exists.
    public func create(properties: SkillProperties, body: String) async throws {
        try validate(properties)
        guard await fileSystem.exists(directory(properties.name)) == false else {
            throw SkillWriteError.nameCollision(properties.name)
        }
        try await fileSystem.write(SkillDocument.serialize(properties: properties, body: body),
                                   to: manifest(properties.name))
    }

    /// Updates an existing skill, optionally renaming it. A rename moves the
    /// directory (preserving resources) before rewriting the manifest.
    public func update(originalName: String, properties: SkillProperties, body: String) async throws {
        try validate(properties)
        guard await fileSystem.exists(directory(originalName)) else {
            throw SkillWriteError.notFound(originalName)
        }
        if properties.name != originalName {
            guard await fileSystem.exists(directory(properties.name)) == false else {
                throw SkillWriteError.nameCollision(properties.name)
            }
            try await fileSystem.moveItem(from: directory(originalName), to: directory(properties.name))
        }
        try await fileSystem.write(SkillDocument.serialize(properties: properties, body: body),
                                   to: manifest(properties.name))
    }

    /// Deletes a skill directory. No-op if it does not exist.
    public func delete(name: String) async throws {
        try await fileSystem.removeItem(directory(name))
    }

    private func validate(_ properties: SkillProperties) throws {
        let errors = SkillDocument.validate(properties)
        guard errors.isEmpty else { throw SkillWriteError.validationFailed(errors) }
    }
}
