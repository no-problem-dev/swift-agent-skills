import Foundation

/// A `SKILL.md` that could not be split into frontmatter and body.
///
/// The fixed messages are copied word for word from the `skills-ref` Python implementation, so
/// tooling can compare output against it. ``invalidYAML(_:)`` is the exception: its detail comes
/// from the Swift YAML parser and does not match the Python text.
public struct SkillParseError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }

    public static let mustStartWithFrontmatter = SkillParseError(
        "SKILL.md must start with YAML frontmatter (---)"
    )
    public static let notProperlyClosed = SkillParseError(
        "SKILL.md frontmatter not properly closed with ---"
    )
    public static let notAMapping = SkillParseError(
        "SKILL.md frontmatter must be a YAML mapping"
    )
    public static func invalidYAML(_ detail: String) -> SkillParseError {
        SkillParseError("Invalid YAML in frontmatter: \(detail)")
    }
    public static func skillMDNotFound(in directory: String) -> SkillParseError {
        SkillParseError("SKILL.md not found in \(directory)")
    }
}

/// Required skill properties are missing or invalid.
///
/// Carries every problem at once instead of failing on the first, so an authoring UI can show
/// the full list in one pass.
public struct SkillValidationError: Error, Equatable, CustomStringConvertible {
    public let errors: [String]
    public init(_ message: String) { self.errors = [message] }
    public init(errors: [String]) { self.errors = errors }
    /// First message only. Empty string when the error was built from an empty list — read
    /// ``errors`` when the count matters.
    public var message: String { errors.first ?? "" }
    public var description: String { errors.joined(separator: "; ") }
}
