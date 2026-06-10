import Foundation

/// In-memory catalog of loaded skills.
///
/// Builtins are seeded first; discovered (disk) skills with the same name
/// override them — matching OpenCode/OpenHands ("register built-in before disk
/// so a user skill can override it").
public actor SkillRegistry {
    private var skills: [String: LoadedSkill] = [:]
    private let builtins: [LoadedSkill]
    private let discovery: (any SkillDiscovering)?
    public private(set) var diagnostics: [SkillDiagnostic] = []

    public init(builtins: [LoadedSkill] = [], discovery: (any SkillDiscovering)? = nil) {
        self.builtins = builtins
        self.discovery = discovery
    }

    /// Seeds builtins, then loads and overlays discovered skills.
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

    public func get(_ name: String) -> LoadedSkill? { skills[name] }

    public func all() -> [LoadedSkill] { skills.values.sorted { $0.name < $1.name } }

    /// Skills visible to the model, filtered by a policy (permissions, opt-outs).
    /// Hidden skills are excluded from the catalog rather than blocked at activation.
    public func available(policy: SkillPolicy = .init()) -> [LoadedSkill] {
        all().filter { policy.isAllowed($0.name) }
    }
}

/// Filters which skills are advertised to the model.
public struct SkillPolicy: Sendable {
    public let isAllowed: @Sendable (_ name: String) -> Bool
    public init(isAllowed: @escaping @Sendable (_ name: String) -> Bool = { _ in true }) {
        self.isAllowed = isAllowed
    }
}
