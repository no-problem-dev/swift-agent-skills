import Foundation

/// Tracks which skills have been activated this session, so the loop can avoid
/// re-injecting the same instructions (dedupe), matching OpenHands
/// `invoked_skills`.
public actor SkillSessionState {
    private var invoked: Set<String> = []

    public init() {}

    /// Records an activation; returns `true` if this is the first time.
    @discardableResult
    public func record(_ name: String) -> Bool {
        invoked.insert(name).inserted
    }

    public func wasInvoked(_ name: String) -> Bool { invoked.contains(name) }

    public var invokedSkills: Set<String> { invoked }
}
