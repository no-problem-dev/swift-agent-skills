import Foundation

/// Raised when `SKILL.md` parsing fails.
///
/// Mirrors `skills-ref` `ParseError`. Messages are reproduced verbatim so a
/// Swift implementation is byte-compatible with the reference validator output.
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

/// Raised when required skill properties are missing or malformed.
///
/// Mirrors `skills-ref` `ValidationError`. Carries one or more messages.
public struct SkillValidationError: Error, Equatable, CustomStringConvertible {
    public let errors: [String]
    public init(_ message: String) { self.errors = [message] }
    public init(errors: [String]) { self.errors = errors }
    public var message: String { errors.first ?? "" }
    public var description: String { errors.joined(separator: "; ") }
}
