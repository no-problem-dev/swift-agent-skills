import Foundation
import AgentSkills

/// Where a discovered skill lives.
public enum SkillLocation: Sendable, Equatable, Codable {
    /// A `SKILL.md` file on a (possibly virtual) filesystem.
    case file(URL)
    /// A skill bundled into the host, identified by name.
    case builtin(name: String)

    /// The skill's base directory (parent of `SKILL.md`), used to resolve
    /// relative `scripts/`, `references/`, `assets/` references. `nil` for builtins.
    public var directory: URL? {
        if case .file(let url) = self { return url.deletingLastPathComponent() }
        return nil
    }
}

/// Standard resource directories a skill may bundle alongside `SKILL.md`.
public struct SkillResources: Sendable, Equatable, Codable {
    public static let directoryNames = ["scripts", "references", "assets"]

    /// Absolute path of the skill's base directory.
    public let root: URL
    /// Relative file paths under `scripts/`.
    public let scripts: [String]
    /// Relative file paths under `references/`.
    public let references: [String]
    /// Relative file paths under `assets/`.
    public let assets: [String]

    public init(root: URL, scripts: [String] = [], references: [String] = [], assets: [String] = []) {
        self.root = root
        self.scripts = scripts
        self.references = references
        self.assets = assets
    }

    public var hasResources: Bool { !scripts.isEmpty || !references.isEmpty || !assets.isEmpty }
}

/// A skill loaded into memory, ready to be cataloged and activated.
///
/// Built leniently: a skill loads even if it fails strict validation (e.g. name
/// doesn't match its directory) as long as it has the essentials (a body and a
/// usable description). Strict issues are surfaced as ``SkillDiagnostic`` warnings.
public struct LoadedSkill: Sendable, Equatable, Identifiable, Codable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let body: String
    public let location: SkillLocation
    public let properties: SkillProperties
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

/// A non-fatal issue encountered while discovering/loading skills.
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

/// The result of a discovery pass.
public struct DiscoveredSkills: Sendable {
    public let skills: [LoadedSkill]
    public let diagnostics: [SkillDiagnostic]
    public init(skills: [LoadedSkill], diagnostics: [SkillDiagnostic]) {
        self.skills = skills
        self.diagnostics = diagnostics
    }
}
