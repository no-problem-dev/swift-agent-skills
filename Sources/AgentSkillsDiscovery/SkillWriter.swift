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
    /// The name does not land on a directory directly under the root — it climbs out with `..`,
    /// carries a path separator, or is empty. Nothing was touched.
    case nameEscapesRoot(String)
}

/// Creates, updates and deletes user-authored skills under one root directory — the write side
/// of skill discovery.
///
/// Everything is validated before it reaches disk, so a skill written here is one discovery
/// loads without warnings. A rename moves the whole directory, keeping bundled `scripts/`,
/// `references/` and `assets/` files with it.
///
/// Every name that reaches disk — ``SkillProperties/name``, the `name` of ``delete(name:)`` and
/// the `originalName` of ``update(originalName:properties:body:)`` — is resolved and checked for
/// containment first, so a name like `../../Documents` is refused rather than followed out of the
/// root.
public struct SkillWriter<FS: FileSystemReading & FileSystemWriting>: Sendable {

    /// Directory the skills live under, one subdirectory per skill — for example
    /// `~/Documents/.agents/skills`.
    public let root: URL
    public let fileSystem: FS

    public init(root: URL, fileSystem: FS) {
        self.root = root
        self.fileSystem = fileSystem
    }

    /// Resolves a skill name to its directory, refusing anything that does not land directly
    /// under ``root``.
    ///
    /// The name is joined to the root and the result is resolved, collapsing `..` and `.`, before
    /// the check — so containment is decided on the path that would actually be written, not on
    /// the text of the name. The layout is one directory per skill, so the test is that the
    /// resolved parent *is* the root: a string prefix would let `<root>-backup` through, and an
    /// unresolved comparison would let `<root>/../../Documents` through.
    ///
    /// The single place containment is decided. Every path this type builds comes from here.
    ///
    /// - Throws: ``SkillWriteError/nameEscapesRoot(_:)``.
    private func directory(_ name: String) throws -> URL {
        let base = root.standardizedFileURL
        let candidate = root.appendingPathComponent(name, isDirectory: true).standardizedFileURL
        guard candidate.deletingLastPathComponent().standardizedFileURL.path == base.path else {
            throw SkillWriteError.nameEscapesRoot(name)
        }
        return candidate
    }

    private func manifest(_ name: String) throws -> URL {
        try directory(name).appendingPathComponent("SKILL.md")
    }

    /// Writes a new skill to `<root>/<name>/SKILL.md`, creating the directories it needs.
    ///
    /// - Parameters:
    ///   - properties: Frontmatter for the new skill; `name` becomes the directory name.
    ///   - body: Markdown instructions placed after the frontmatter.
    /// - Throws: ``SkillWriteError/validationFailed(_:)`` before touching disk,
    ///   ``SkillWriteError/nameEscapesRoot(_:)`` when the name does not land under the root, or
    ///   ``SkillWriteError/nameCollision(_:)`` when that directory already exists.
    public func create(properties: SkillProperties, body: String) async throws {
        try validate(properties)
        guard await fileSystem.exists(try directory(properties.name)) == false else {
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
    ///   - originalName: Name the skill currently has on disk. Checked for containment under the
    ///     root before anything is read or moved.
    ///   - properties: New frontmatter. A changed `name` renames the directory.
    ///   - body: Markdown that replaces the existing body entirely.
    /// - Throws: ``SkillWriteError/validationFailed(_:)`` before touching disk,
    ///   ``SkillWriteError/nameEscapesRoot(_:)`` when either name leaves the root,
    ///   ``SkillWriteError/notFound(_:)`` when `originalName` does not exist, or
    ///   ``SkillWriteError/nameCollision(_:)`` when the new name is taken.
    public func update(originalName: String, properties: SkillProperties, body: String) async throws {
        try validate(properties)
        let source = try directory(originalName)
        guard await fileSystem.exists(source) else {
            throw SkillWriteError.notFound(originalName)
        }
        if properties.name != originalName {
            let destination = try directory(properties.name)
            guard await fileSystem.exists(destination) == false else {
                throw SkillWriteError.nameCollision(properties.name)
            }
            try await fileSystem.moveItem(from: source, to: destination)
        }
        try await fileSystem.write(SkillDocument.serialize(properties: properties, body: body),
                                   to: manifest(properties.name))
    }

    /// Removes a skill's directory and everything inside it.
    ///
    /// Deleting a skill that is not there is not an error. A name that does not land on a
    /// directory directly under the root is refused before anything is removed.
    ///
    /// - Parameter name: Directory name of the skill to remove.
    /// - Throws: ``SkillWriteError/nameEscapesRoot(_:)`` when the name leaves the root.
    public func delete(name: String) async throws {
        try await fileSystem.removeItem(try directory(name))
    }

    private func validate(_ properties: SkillProperties) throws {
        let errors = SkillDocument.validate(properties)
        guard errors.isEmpty else { throw SkillWriteError.validationFailed(errors) }
    }
}
