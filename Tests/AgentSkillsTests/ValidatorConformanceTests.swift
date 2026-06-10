import Testing
import Foundation
import PersistenceTesting
@testable import AgentSkills

/// Ports `skills-ref/tests/test_validator.py` (24 cases) for byte-level parity.
@Suite("Validator conformance (skills-ref test_validator.py)")
struct ValidatorConformanceTests {

    private let root = URL(fileURLWithPath: "/tmp/validator")

    /// Writes a SKILL.md under `<root>/<dirName>/` and validates that directory.
    private func validate(dirName: String, skillMD: String?) async -> [String] {
        let fs = InMemoryFileSystem()
        let skillDir = root.appendingPathComponent(dirName)
        if let skillMD {
            await fs.addFile(skillDir.appendingPathComponent("SKILL.md"), string: skillMD)
        } else {
            await fs.addDirectory(skillDir)
        }
        return await SkillValidator.validate(skillDirectory: skillDir, fileSystem: fs)
    }

    @Test("valid skill")
    func validSkill() async {
        let errors = await validate(dirName: "my-skill", skillMD: """
        ---
        name: my-skill
        description: A test skill
        ---
        # My Skill
        """)
        #expect(errors == [])
    }

    @Test("nonexistent path")
    func nonexistentPath() async {
        let fs = InMemoryFileSystem()
        let errors = await SkillValidator.validate(skillDirectory: root.appendingPathComponent("nope"), fileSystem: fs)
        #expect(errors.count == 1)
        #expect(errors[0].contains("does not exist"))
    }

    @Test("not a directory")
    func notADirectory() async {
        let fs = InMemoryFileSystem()
        let file = root.appendingPathComponent("file.txt")
        await fs.addFile(file, string: "test")
        let errors = await SkillValidator.validate(skillDirectory: file, fileSystem: fs)
        #expect(errors.count == 1)
        #expect(errors[0].contains("Not a directory"))
    }

    @Test("missing SKILL.md")
    func missingSkillMD() async {
        let errors = await validate(dirName: "my-skill", skillMD: nil)
        #expect(errors.count == 1)
        #expect(errors[0].contains("Missing required file: SKILL.md"))
    }

    @Test("invalid name uppercase")
    func invalidNameUppercase() async {
        let errors = await validate(dirName: "MySkill", skillMD: """
        ---
        name: MySkill
        description: A test skill
        ---
        Body
        """)
        #expect(errors.contains { $0.contains("lowercase") })
    }

    @Test("name too long")
    func nameTooLong() async {
        let long = String(repeating: "a", count: 70)
        let errors = await validate(dirName: long, skillMD: """
        ---
        name: \(long)
        description: A test skill
        ---
        Body
        """)
        #expect(errors.contains { $0.contains("exceeds") && $0.contains("character limit") })
    }

    @Test("name leading hyphen")
    func nameLeadingHyphen() async {
        let errors = await validate(dirName: "-my-skill", skillMD: """
        ---
        name: -my-skill
        description: A test skill
        ---
        Body
        """)
        #expect(errors.contains { $0.contains("cannot start or end with a hyphen") })
    }

    @Test("name consecutive hyphens")
    func nameConsecutiveHyphens() async {
        let errors = await validate(dirName: "my--skill", skillMD: """
        ---
        name: my--skill
        description: A test skill
        ---
        Body
        """)
        #expect(errors.contains { $0.contains("consecutive hyphens") })
    }

    @Test("name invalid characters")
    func nameInvalidCharacters() async {
        let errors = await validate(dirName: "my_skill", skillMD: """
        ---
        name: my_skill
        description: A test skill
        ---
        Body
        """)
        #expect(errors.contains { $0.contains("invalid characters") })
    }

    @Test("name directory mismatch")
    func nameDirectoryMismatch() async {
        let errors = await validate(dirName: "wrong-name", skillMD: """
        ---
        name: correct-name
        description: A test skill
        ---
        Body
        """)
        #expect(errors.contains { $0.contains("must match skill name") })
    }

    @Test("unexpected fields")
    func unexpectedFields() async {
        let errors = await validate(dirName: "my-skill", skillMD: """
        ---
        name: my-skill
        description: A test skill
        unknown_field: should not be here
        ---
        Body
        """)
        #expect(errors.contains { $0.contains("Unexpected fields") })
    }

    @Test("valid with all fields")
    func validWithAllFields() async {
        let errors = await validate(dirName: "my-skill", skillMD: """
        ---
        name: my-skill
        description: A test skill
        license: MIT
        metadata:
          author: Test
        ---
        Body
        """)
        #expect(errors == [])
    }

    @Test("allowed-tools accepted")
    func allowedToolsAccepted() async {
        let errors = await validate(dirName: "my-skill", skillMD: """
        ---
        name: my-skill
        description: A test skill
        allowed-tools: Bash(jq:*) Bash(git:*)
        ---
        Body
        """)
        #expect(errors == [])
    }

    @Test("i18n Chinese name")
    func i18nChinese() async {
        let errors = await validate(dirName: "技能", skillMD: """
        ---
        name: 技能
        description: A skill with Chinese name
        ---
        Body
        """)
        #expect(errors == [])
    }

    @Test("i18n Russian name with hyphens")
    func i18nRussianHyphens() async {
        let errors = await validate(dirName: "мой-навык", skillMD: """
        ---
        name: мой-навык
        description: A skill with Russian name
        ---
        Body
        """)
        #expect(errors == [])
    }

    @Test("i18n Russian lowercase valid")
    func i18nRussianLowercase() async {
        let errors = await validate(dirName: "навык", skillMD: """
        ---
        name: навык
        description: A skill with Russian lowercase name
        ---
        Body
        """)
        #expect(errors == [])
    }

    @Test("i18n Russian uppercase rejected")
    func i18nRussianUppercase() async {
        let errors = await validate(dirName: "НАВЫК", skillMD: """
        ---
        name: НАВЫК
        description: A skill with Russian uppercase name
        ---
        Body
        """)
        #expect(errors.contains { $0.contains("lowercase") })
    }

    @Test("description too long")
    func descriptionTooLong() async {
        let long = String(repeating: "x", count: 1100)
        let errors = await validate(dirName: "my-skill", skillMD: """
        ---
        name: my-skill
        description: \(long)
        ---
        Body
        """)
        #expect(errors.contains { $0.contains("exceeds") && $0.contains("1024") })
    }

    @Test("valid compatibility")
    func validCompatibility() async {
        let errors = await validate(dirName: "my-skill", skillMD: """
        ---
        name: my-skill
        description: A test skill
        compatibility: Requires Python 3.11+
        ---
        Body
        """)
        #expect(errors == [])
    }

    @Test("compatibility too long")
    func compatibilityTooLong() async {
        let long = String(repeating: "x", count: 550)
        let errors = await validate(dirName: "my-skill", skillMD: """
        ---
        name: my-skill
        description: A test skill
        compatibility: \(long)
        ---
        Body
        """)
        #expect(errors.contains { $0.contains("exceeds") && $0.contains("500") })
    }

    @Test("NFKC normalization (decomposed name matches composed dir)")
    func nfkcNormalization() async {
        let composed = "café"
        let decomposed = "cafe\u{0301}"
        let errors = await validate(dirName: composed, skillMD: """
        ---
        name: \(decomposed)
        description: A test skill
        ---
        Body
        """)
        #expect(errors == [])
    }
}
