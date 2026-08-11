import Foundation
import AgentSkills
import PersistenceCore

/// A place skills can be scanned for on demand.
public protocol SkillDiscovering: Sendable {
    /// Scans the source and returns every skill it could load, plus what went wrong.
    ///
    /// Implementations are lenient: a skill that fails strict validation still loads as long as
    /// it has a description, and the failures are recorded in ``DiscoveredSkills/diagnostics``.
    /// Nothing throws — a skill that cannot be read or parsed becomes an `.error` diagnostic and
    /// is dropped from the result, so a caller that ignores diagnostics silently loses skills.
    func discover() async -> DiscoveredSkills
}

/// Which directories a filesystem scan covers, and the limits it runs under.
public struct SkillDiscoveryConfig: Sendable {
    /// Where the project-level walk starts. Every directory from here up to ``worktreeStop`` is
    /// checked for skill subdirectories.
    public var projectRoot: URL?
    /// Last directory the upward walk visits, inclusive — usually the git or worktree root.
    /// Leave it `nil` to scan ``projectRoot`` alone and not walk up at all.
    public var worktreeStop: URL?
    /// Home directory holding user-level skills. `nil` skips the user scope entirely.
    public var homeDirectory: URL?
    /// Scan `.agents/skills/`, the cross-client standard location.
    public var scanAgentsDir: Bool
    /// Scan `.claude/skills/`, for skills already written for Claude Code. It is scanned after
    /// `.agents/skills/`, so when both hold the same name in one directory the Claude copy wins.
    public var scanClaudeDir: Bool
    /// Extra skill roots, scanned last and at the highest precedence.
    ///
    /// They outrank project and user skills, and ``isTrusted`` is not consulted for them.
    public var extraRoots: [URL]
    /// How deep below a root the scan descends. A directory holding a `SKILL.md` is treated as a
    /// skill and never descended into, so nested skills are invisible regardless of this value.
    public var maxDepth: Int
    /// Directory budget per root. When it runs out the scan for that root stops where it is and
    /// records no diagnostic, so a very large tree quietly yields a partial list.
    public var maxEntries: Int
    /// Gate applied to project-scope roots only. Returning `false` skips the root; user roots and
    /// ``extraRoots`` are scanned without asking.
    public var isTrusted: @Sendable (URL) -> Bool

    public init(
        projectRoot: URL? = nil,
        worktreeStop: URL? = nil,
        homeDirectory: URL? = nil,
        scanAgentsDir: Bool = true,
        scanClaudeDir: Bool = true,
        extraRoots: [URL] = [],
        maxDepth: Int = 6,
        maxEntries: Int = 2000,
        isTrusted: @escaping @Sendable (URL) -> Bool = { _ in true }
    ) {
        self.projectRoot = projectRoot
        self.worktreeStop = worktreeStop
        self.homeDirectory = homeDirectory
        self.scanAgentsDir = scanAgentsDir
        self.scanClaudeDir = scanClaudeDir
        self.extraRoots = extraRoots
        self.maxDepth = maxDepth
        self.maxEntries = maxEntries
        self.isTrusted = isTrusted
    }
}

/// Where a skill was found. Ranks the sources when two skills share a name: explicit beats
/// project, project beats user.
public enum SkillScope: Int, Sendable, Comparable {
    case user = 0
    case project = 1
    case explicit = 2
    public static func < (lhs: SkillScope, rhs: SkillScope) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Scans a filesystem for `SKILL.md` files and loads them leniently.
///
/// Roots are visited user first, then project — from ``SkillDiscoveryConfig/projectRoot``
/// upward — then ``SkillDiscoveryConfig/extraRoots``. On a name clash the higher scope wins and
/// the loser is reported as a warning; between two roots of the *same* scope the one visited
/// later wins, so an ancestor directory shadows the project root itself.
///
/// The filesystem arrives by injection, so the same scan runs against a real tree or an
/// in-memory one. It only ever reads and lists — no skill content is executed here.
public struct FileSystemSkillDiscovery<FS: FileSystemReading>: SkillDiscovering {
    private let config: SkillDiscoveryConfig
    private let fileSystem: FS

    public init(config: SkillDiscoveryConfig, fileSystem: FS) {
        self.config = config
        self.fileSystem = fileSystem
    }

    /// Scans every configured root and returns the surviving skills, sorted by name.
    ///
    /// A skill is dropped, with an `.error` diagnostic, when its `SKILL.md` cannot be read or
    /// parsed or when it has no description. Every other rule violation — a `name` that does not
    /// match the directory, an over-long description — is a warning and the skill still loads.
    /// Each shadowed duplicate also produces a warning naming the scope that won.
    public func discover() async -> DiscoveredSkills {
        var loaded: [(scope: SkillScope, skill: LoadedSkill)] = []
        var diagnostics: [SkillDiagnostic] = []

        for (scope, root) in await scanRoots() {
            if scope == .project && !config.isTrusted(root) { continue }
            for manifest in await findManifests(in: root) {
                let (skill, diags) = await loadSkill(manifest: manifest)
                diagnostics += diags
                if let skill { loaded.append((scope, skill)) }
            }
        }

        // Merge by name; higher scope wins, with a collision warning.
        var byName: [String: (scope: SkillScope, skill: LoadedSkill)] = [:]
        for entry in loaded {
            if let existing = byName[entry.skill.name] {
                let (winner, loser) = entry.scope >= existing.scope ? (entry, existing) : (existing, entry)
                byName[entry.skill.name] = winner
                diagnostics.append(SkillDiagnostic(
                    .warning,
                    location: loser.skill.location.directory?.path ?? loser.skill.name,
                    message: "Duplicate skill name '\(entry.skill.name)' — shadowed by \(winner.scope)."
                ))
            } else {
                byName[entry.skill.name] = entry
            }
        }

        let skills = byName.values.map(\.skill).sorted { $0.name < $1.name }
        return DiscoveredSkills(skills: skills, diagnostics: diagnostics)
    }

    // MARK: - Roots

    private func scanRoots() async -> [(SkillScope, URL)] {
        var roots: [(SkillScope, URL)] = []
        let subdirs = skillSubdirNames()

        if let home = config.homeDirectory {
            for sub in subdirs {
                let root = home.appendingPathComponent(sub)
                if await fileSystem.isDirectory(root) { roots.append((.user, root)) }
            }
        }

        for dir in projectWalk() {
            for sub in subdirs {
                let root = dir.appendingPathComponent(sub)
                if await fileSystem.isDirectory(root) { roots.append((.project, root)) }
            }
        }

        for root in config.extraRoots where await fileSystem.isDirectory(root) {
            roots.append((.explicit, root))
        }
        return roots
    }

    private func skillSubdirNames() -> [String] {
        var names: [String] = []
        if config.scanAgentsDir { names.append(".agents/skills") }
        if config.scanClaudeDir { names.append(".claude/skills") }
        return names
    }

    /// Directories from `projectRoot` up to and including `worktreeStop`.
    private func projectWalk() -> [URL] {
        guard let start = config.projectRoot?.standardizedFileURL else { return [] }
        var dirs: [URL] = []
        var current = start
        let stop = config.worktreeStop?.standardizedFileURL
        while true {
            dirs.append(current)
            if current.path == stop?.path { break }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }  // reached filesystem root
            if stop == nil && current.path == start.path { break }  // no stop → just the start dir
            current = parent
        }
        return dirs
    }

    // MARK: - Scanning a root for SKILL.md

    private func findManifests(in root: URL) async -> [URL] {
        var manifests: [URL] = []
        var visited = 0
        var queue: [(URL, Int)] = [(root, 0)]

        while !queue.isEmpty {
            let (dir, depth) = queue.removeFirst()
            visited += 1
            if visited > config.maxEntries { break }

            guard let entries = try? await fileSystem.contentsOfDirectory(dir) else { continue }
            if let manifest = await SkillFrontmatter.findSkillMD(in: dir, fileSystem: fileSystem) {
                manifests.append(manifest)
                continue  // a skill dir; don't descend into its resource subdirs
            }
            if depth >= config.maxDepth { continue }
            for entry in entries where await shouldDescend(entry) {
                queue.append((entry, depth + 1))
            }
        }
        return manifests.sorted { $0.path < $1.path }
    }

    private func shouldDescend(_ url: URL) async -> Bool {
        guard await fileSystem.isDirectory(url) else { return false }
        let name = url.lastPathComponent
        return name != ".git" && name != "node_modules"
    }

    // MARK: - Lenient load

    private func loadSkill(manifest: URL) async -> (LoadedSkill?, [SkillDiagnostic]) {
        let skillDir = manifest.deletingLastPathComponent()
        let location = skillDir.path

        let content: String
        do {
            content = try await fileSystem.readString(manifest)
        } catch {
            return (nil, [SkillDiagnostic(.error, location: location, message: "Cannot read SKILL.md: \(error)")])
        }

        let frontmatter: StructuredFrontmatter
        do {
            let (parsed, body) = try SkillFrontmatter.parseFrontmatter(content)
            frontmatter = StructuredFrontmatter(object: parsed, body: body)
        } catch {
            return (nil, [SkillDiagnostic(.error, location: location, message: "Unparseable SKILL.md: \(error)")])
        }

        var diagnostics: [SkillDiagnostic] = []
        let dirName = skillDir.lastPathComponent

        // Description is essential for disclosure → skip if missing.
        guard let description = frontmatter.object["description"]?.string, !description.trimmed.isEmpty else {
            return (nil, [SkillDiagnostic(.error, location: location, message: "Skill is missing a description; skipped.")])
        }
        // Name: fall back to the directory name when absent.
        let name = frontmatter.object["name"]?.string?.trimmed.nonEmpty ?? dirName

        // Strict issues become warnings (warn-and-load).
        for issue in SkillValidator.validate(frontmatter: frontmatter.object, directoryName: dirName) {
            // Don't re-warn the description (already required above) — keep name/field issues.
            if issue.contains("description") { continue }
            diagnostics.append(SkillDiagnostic(.warning, location: location, message: issue))
        }

        let properties = SkillProperties(
            name: name,
            description: description.trimmed,
            license: frontmatter.object["license"]?.string,
            compatibility: frontmatter.object["compatibility"]?.string,
            allowedTools: frontmatter.object["allowed-tools"]?.string,
            metadata: SkillProperties.stringifiedMetadata(frontmatter.object["metadata"])
        )
        let resources = await SkillResourceLoader.discover(in: skillDir, fileSystem: fileSystem)

        let skill = LoadedSkill(
            name: name,
            description: description.trimmed,
            body: frontmatter.body,
            location: .file(manifest),
            properties: properties,
            resources: resources
        )
        return (skill, diagnostics)
    }
}

import StructuredDataCore

/// Keeps the parsed mapping and the body together while `loadSkill` builds a skill.
private struct StructuredFrontmatter {
    let object: OrderedObject
    let body: String
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
