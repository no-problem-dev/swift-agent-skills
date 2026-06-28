import Foundation

/// `SKILL.md` のパース失敗時にスローされるエラー。
///
/// `skills-ref` の `ParseError` を移植。メッセージは参照実装と逐語的に一致させており、
/// `skills-ref validate` の出力とバイト互換。
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

/// 必須スキルプロパティの欠損または不正値を示すエラー。
///
/// `skills-ref` の `ValidationError` を移植。1 件以上のメッセージを保持する。
public struct SkillValidationError: Error, Equatable, CustomStringConvertible {
    public let errors: [String]
    public init(_ message: String) { self.errors = [message] }
    public init(errors: [String]) { self.errors = errors }
    public var message: String { errors.first ?? "" }
    public var description: String { errors.joined(separator: "; ") }
}
