import Foundation
import Testing
import StructuredDataCore
@testable import AgentSkills

@Suite("SkillDocument authoring")
struct SkillDocumentTests {

    /// The authoring guarantee: a serialized document parses back to the same
    /// properties and body, and passes strict validation.
    private func assertRoundTrips(
        _ properties: SkillProperties,
        body: String,
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) throws {
        let document = SkillDocument.serialize(properties: properties, body: body)
        let (frontmatter, parsedBody) = try SkillFrontmatter.parseFrontmatter(document)
        let reparsed = try SkillProperties(frontmatter: frontmatter)
        #expect(reparsed == properties, sourceLocation: sourceLocation)
        #expect(parsedBody == body.trimmingCharacters(in: .whitespacesAndNewlines), sourceLocation: sourceLocation)

        let errors = SkillValidator.validate(frontmatter: frontmatter, directoryName: properties.name)
        #expect(errors.isEmpty, "validation errors: \(errors)", sourceLocation: sourceLocation)
    }

    @Test("minimal skill (name + description) round-trips and validates")
    func minimal() throws {
        try assertRoundTrips(
            SkillProperties(name: "deep-research", description: "Run a multi-source investigation."),
            body: "# Deep Research\n\nDo the thing."
        )
    }

    @Test("all optional fields round-trip")
    func allFields() throws {
        try assertRoundTrips(
            SkillProperties(
                name: "cite-sources",
                description: "Add citations. Use when: a draft needs sourcing.",
                license: "Apache-2.0",
                compatibility: "Requires network access.",
                allowedTools: "Bash(git:*) Read",
                metadata: ["version": "1.0", "author": "no-problem"]
            ),
            body: "Body text."
        )
    }

    @Test("description with structural characters round-trips")
    func structuralDescription() throws {
        try assertRoundTrips(
            SkillProperties(name: "compare-options", description: "Compare A: pros, cons; then decide [final]."),
            body: "x"
        )
    }

    @Test("empty body produces a frontmatter-only document")
    func emptyBody() throws {
        try assertRoundTrips(
            SkillProperties(name: "fact-check", description: "Verify claims."),
            body: ""
        )
    }

    @Test("frontmatter is emitted in canonical ALLOWED_FIELDS order")
    func canonicalOrder() {
        let props = SkillProperties(
            name: "x", description: "y", license: "MIT",
            compatibility: "z", allowedTools: "Read", metadata: ["k": "v"]
        )
        let object = SkillDocument.frontmatter(props)
        #expect(object.keys == ["name", "description", "license", "compatibility", "allowed-tools", "metadata"])
    }

    @Test("optional fields are omitted when absent")
    func omitsAbsent() {
        let object = SkillDocument.frontmatter(SkillProperties(name: "x", description: "y"))
        #expect(object.keys == ["name", "description"])
    }

    @Test("metadata value 1.0 survives as the string \"1.0\"")
    func metadataStaysString() throws {
        let props = SkillProperties(name: "x", description: "y", metadata: ["version": "1.0"])
        let document = SkillDocument.serialize(properties: props, body: "")
        let (frontmatter, _) = try SkillFrontmatter.parseFrontmatter(document)
        let reparsed = try SkillProperties(frontmatter: frontmatter)
        #expect(reparsed.metadata["version"] == "1.0")
    }

    @Test("strict validation gate rejects an invalid name")
    func gateRejectsInvalid() {
        let props = SkillProperties(name: "Has Spaces", description: "y")
        let errors = SkillDocument.validate(props)
        #expect(!errors.isEmpty)
    }

    @Test("strict validation gate accepts a valid skill")
    func gateAcceptsValid() {
        let props = SkillProperties(name: "valid-name", description: "y", metadata: ["version": "1.0"])
        #expect(SkillDocument.validate(props).isEmpty)
    }
}
