import Foundation

/// In-memory catalog of loaded skills, keyed by name.
///
/// Builtins are seeded first and then overwritten by discovered skills with the same name, so a
/// user can replace a builtin just by shipping one that matches.
///
/// Nothing is cached across calls and nothing watches the filesystem: the registry holds the
/// snapshot taken by the last ``load()`` and only re-reads when ``load()`` is called again.
public actor SkillRegistry {
    private var skills: [String: LoadedSkill] = [:]
    private let builtins: [LoadedSkill]
    private let discovery: (any SkillDiscovering)?
    public private(set) var diagnostics: [SkillDiagnostic] = []

    public init(builtins: [LoadedSkill] = [], discovery: (any SkillDiscovering)? = nil) {
        self.builtins = builtins
        self.discovery = discovery
    }

    /// Rebuilds the catalog: clears it, seeds the builtins, then lets discovery overwrite them.
    ///
    /// Call this before any lookup. Safe to repeat — each call reruns discovery and replaces
    /// ``diagnostics``, which is the only way to pick up a skill added since the last call.
    public func load() async {
        skills.removeAll()
        diagnostics.removeAll()
        for skill in builtins {
            skills[skill.name] = skill
        }
        if let discovery {
            let discovered = await discovery.discover()
            diagnostics = discovered.diagnostics
            for skill in discovered.skills {
                skills[skill.name] = skill  // disk overrides builtin
            }
        }
    }

    /// Looks a skill up by exact name; `nil` until the registry has been loaded.
    ///
    /// Ignores ``SkillPolicy``, so a skill hidden from the catalog still resolves here. That is
    /// what lets ``SkillActivator`` tell a hidden skill apart from a typo.
    public func get(_ name: String) -> LoadedSkill? { skills[name] }

    /// Every loaded skill, sorted by name, policy-hidden ones included. Empty before ``load()``.
    public func all() -> [LoadedSkill] { skills.values.sorted { $0.name < $1.name } }

    /// The skills a model should be told about.
    ///
    /// A hidden skill is left out of the catalog rather than refused at activation time, so the
    /// model never sees a name it cannot use.
    ///
    /// - Parameter policy: Filter to apply. The default advertises everything.
    public func available(policy: SkillPolicy = .init()) -> [LoadedSkill] {
        all().filter { policy.isAllowed($0.name) }
    }
}

/// Decides which skills are advertised to the model.
///
/// Excluding a skill here does not unregister it: ``SkillRegistry/get(_:)`` still returns it and
/// ``SkillActivator`` reports it as not model-invocable, which is how trigger-only skills work.
public struct SkillPolicy: Sendable {
    public let isAllowed: @Sendable (_ name: String) -> Bool
    public init(isAllowed: @escaping @Sendable (_ name: String) -> Bool = { _ in true }) {
        self.isAllowed = isAllowed
    }
}
