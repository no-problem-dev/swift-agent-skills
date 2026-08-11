import Foundation
import AgentSkills

/// Where a loaded skill's content came from.
public enum SkillLocation: Sendable, Equatable, Codable {
    /// A `SKILL.md` on whichever filesystem the scan ran against — a real path, or a virtual one
    /// in tests.
    case file(URL)
    /// Compiled into the host. There is no directory, so bundled resources cannot be resolved.
    case builtin(name: String)

    /// Directory that `scripts/`, `references/` and `assets/` paths resolve against.
    ///
    /// `nil` for builtins, which is what makes a builtin unable to carry resource files.
    public var directory: URL? {
        if case .file(let url) = self { return url.deletingLastPathComponent() }
        return nil
    }
}

/// Files a skill ships next to its `SKILL.md`, listed but never read.
///
/// Paths in each list are relative to *that* subdirectory, not to ``root``: a file at
/// `<root>/scripts/util/run.sh` is stored as `util/run.sh`. Prepend the subdirectory name before
/// resolving one against ``root``.
public struct SkillResources: Sendable, Equatable, Codable {
    /// The three subdirectory names the standard reserves. Anything else next to `SKILL.md` is
    /// ignored.
    public static let directoryNames = ["scripts", "references", "assets"]

    /// Absolute path of the skill's own directory, the one holding `SKILL.md`.
    public let root: URL
    /// Executable helpers, relative to `<root>/scripts/`.
    public let scripts: [String]
    /// Reference material the model can read on demand, relative to `<root>/references/`.
    public let references: [String]
    /// Static files the skill uses, relative to `<root>/assets/`.
    public let assets: [String]

    public init(root: URL, scripts: [String] = [], references: [String] = [], assets: [String] = []) {
        self.root = root
        self.scripts = scripts
        self.references = references
        self.assets = assets
    }

    public var hasResources: Bool { !scripts.isEmpty || !references.isEmpty || !assets.isEmpty }
}

/// A skill held in memory, ready to be catalogued and activated.
///
/// Existing here does not mean the skill was valid. Discovery loads a skill whose `name` does
/// not match its directory, or whose description is over the limit, and records the problems as
/// ``SkillDiagnostic`` warnings instead.
public struct LoadedSkill: Sendable, Equatable, Identifiable, Codable {
    /// Same as the skill's name, which is also the key the registry deduplicates on.
    public var id: String { name }
    /// Name the skill is invoked by. Falls back to the directory name when the frontmatter has
    /// none, so it does not always equal `properties.name` as written on disk.
    public let name: String
    public let description: String
    /// Markdown after the frontmatter. Legitimately empty — a skill with no instructions still
    /// loads.
    public let body: String
    public let location: SkillLocation
    public let properties: SkillProperties
    /// Bundled files, or `nil` when the skill has none — which is always the case for builtins.
    public let resources: SkillResources?

    public init(
        name: String,
        description: String,
        body: String,
        location: SkillLocation,
        properties: SkillProperties,
        resources: SkillResources? = nil
    ) {
        self.name = name
        self.description = description
        self.body = body
        self.location = location
        self.properties = properties
        self.resources = resources
    }
}

/// Something that went wrong during a scan without stopping it.
///
/// Severity says what happened to the skill: a `warning` means it loaded anyway, an `error`
/// means it was skipped and will not appear in ``DiscoveredSkills/skills``.
public struct SkillDiagnostic: Sendable, Equatable, Codable {
    public enum Severity: String, Sendable, Codable { case warning, error }
    public let severity: Severity
    public let location: String
    public let message: String

    public init(_ severity: Severity, location: String, message: String) {
        self.severity = severity
        self.location = location
        self.message = message
    }
}

/// The outcome of one scan.
public struct DiscoveredSkills: Sendable {
    /// Surviving skills, deduplicated by name and sorted by it.
    public let skills: [LoadedSkill]
    /// Everything that went wrong. Skipped skills only show up here, so a scan that returns few
    /// skills and no diagnostics found nothing, while few skills and many errors is a broken tree.
    public let diagnostics: [SkillDiagnostic]
    public init(skills: [LoadedSkill], diagnostics: [SkillDiagnostic]) {
        self.skills = skills
        self.diagnostics = diagnostics
    }
}
