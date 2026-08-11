import Foundation

/// Tracks which skills a conversation has already activated.
///
/// Lets a loop inject a skill's instructions once instead of on every call. Use one instance per
/// conversation: share it across conversations and the second one sees every skill as already
/// activated, create a fresh one per turn and the de-duplication never fires.
public actor SkillSessionState {
    private var invoked: Set<String> = []

    public init() {}

    /// Records an activation and reports whether it was the first one for this name.
    ///
    /// - Parameter name: Skill that was just activated.
    /// - Returns: `true` on the first activation, `false` on every later one.
    @discardableResult
    public func record(_ name: String) -> Bool {
        invoked.insert(name).inserted
    }

    /// Whether this name has already been recorded in this session.
    public func wasInvoked(_ name: String) -> Bool { invoked.contains(name) }

    public var invokedSkills: Set<String> { invoked }
}
