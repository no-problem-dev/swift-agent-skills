import Foundation
import AgentSkills
import PersistenceCore

/// Why a skill could not be written.
public enum SkillWriteError: Error, Equatable {
    /// Strict validation rejected the properties, before anything was written. Carries every
    /// message.
    case validationFailed([String])
    /// A directory with that name already exists under the root.
    case nameCollision(String)
    /// No skill directory with that name exists to update.
    case notFound(String)
}

/// Creates, updates and deletes user-authored skills under one root directory — the write side
/// of skill discovery.
///
/// Everything is validated before it reaches disk, so a skill written here is one discovery
/// loads without warnings. A rename moves the whole directory, keeping bundled `scripts/`,
/// `references/` and `assets/` files with it.
///
/// Only ``SkillProperties/name`` goes through validation. ``delete(name:)`` and the
/// `originalName` of ``update(originalName:properties:body:)`` are appended to the root exactly
/// as given, so never pass unchecked input to those.
public struct SkillWriter<FS: FileSystemReading & FileSystemWriting>: Sendable {

    /// Directory the skills live under, one subdirectory per skill — for example
    /// `~/Documents/.agents/skills`.
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

    /// Writes a new skill to `<root>/<name>/SKILL.md`, creating the directories it needs.
    ///
    /// - Parameters:
    ///   - properties: Frontmatter for the new skill; `name` becomes the directory name.
    ///   - body: Markdown instructions placed after the frontmatter.
    /// - Throws: ``SkillWriteError/validationFailed(_:)`` before touching disk, or
    ///   ``SkillWriteError/nameCollision(_:)`` when that directory already exists.
    public func create(properties: SkillProperties, body: String) async throws {
        try validate(properties)
        guard await fileSystem.exists(directory(properties.name)) == false else {
            throw SkillWriteError.nameCollision(properties.name)
        }
        try await fileSystem.write(SkillDocument.serialize(properties: properties, body: body),
                                   to: manifest(properties.name))
    }

    /// Rewrites an existing skill, renaming its directory first when the name changed.
    ///
    /// The move and the write are separate steps and not a transaction: if the write fails after
    /// a rename, the skill sits under its new directory name with its old manifest.
    ///
    /// - Parameters:
    ///   - originalName: Name the skill currently has on disk. Not validated — joined to the
    ///     root as given.
    ///   - properties: New frontmatter. A changed `name` renames the directory.
    ///   - body: Markdown that replaces the existing body entirely.
    /// - Throws: ``SkillWriteError/validationFailed(_:)`` before touching disk,
    ///   ``SkillWriteError/notFound(_:)`` when `originalName` does not exist, or
    ///   ``SkillWriteError/nameCollision(_:)`` when the new name is taken.
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

    /// Removes a skill's directory and everything inside it.
    ///
    /// Deleting a skill that is not there is not an error. The name is not validated and is
    /// joined to the root as given.
    ///
    /// - Parameter name: Directory name of the skill to remove.
    public func delete(name: String) async throws {
        try await fileSystem.removeItem(directory(name))
    }

    private func validate(_ properties: SkillProperties) throws {
        let errors = SkillDocument.validate(properties)
        guard errors.isEmpty else { throw SkillWriteError.validationFailed(errors) }
    }
}
