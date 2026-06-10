// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-agent-skills",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "AgentSkills", targets: ["AgentSkills"]),
        .library(name: "AgentSkillsDiscovery", targets: ["AgentSkillsDiscovery"]),
        .library(name: "AgentSkillsRuntime", targets: ["AgentSkillsRuntime"]),
        .library(name: "AgentSkillsTool", targets: ["AgentSkillsTool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/no-problem-dev/swift-structured-data.git", from: "1.3.0"),
        .package(url: "https://github.com/no-problem-dev/swift-persistence.git", from: "2.1.1"),
        .package(url: "https://github.com/no-problem-dev/swift-llm-client.git", from: "3.5.0"),
    ],
    targets: [
        // Layer 1: strict Agent Skills standard core (parser / validator / catalog).
        // Mirrors agentskills.io `skills-ref` (parser.py / validator.py / prompt.py).
        .target(
            name: "AgentSkills",
            dependencies: [
                .product(name: "StructuredDataCore", package: "swift-structured-data"),
                .product(name: "YAMLParsing", package: "swift-structured-data"),
                .product(name: "PersistenceCore", package: "swift-persistence"),
            ]
        ),
        .testTarget(
            name: "AgentSkillsTests",
            dependencies: [
                "AgentSkills",
                .product(name: "PersistenceTesting", package: "swift-persistence"),
            ]
        ),

        // Layer 2: lenient multi-root discovery (warn-and-load) over an injected
        // filesystem. Derives behavior from OpenHands + the official client guide.
        .target(
            name: "AgentSkillsDiscovery",
            dependencies: [
                "AgentSkills",
                .product(name: "PersistenceCore", package: "swift-persistence"),
            ]
        ),
        .testTarget(
            name: "AgentSkillsDiscoveryTests",
            dependencies: [
                "AgentSkillsDiscovery",
                .product(name: "PersistenceTesting", package: "swift-persistence"),
                .product(name: "PersistenceFileSystem", package: "swift-persistence"),
            ]
        ),

        // Layer 3a: loop activation logic (catalog / activation / dedup / render).
        // Pure — no LLM dependency, fully testable in isolation.
        .target(
            name: "AgentSkillsRuntime",
            dependencies: ["AgentSkillsDiscovery"]
        ),
        .testTarget(
            name: "AgentSkillsRuntimeTests",
            dependencies: [
                "AgentSkillsRuntime",
                .product(name: "PersistenceTesting", package: "swift-persistence"),
            ]
        ),

        // Layer 3b: the `Tool` adapter — the only target coupled to an LLM stack.
        .target(
            name: "AgentSkillsTool",
            dependencies: [
                "AgentSkillsRuntime",
                .product(name: "LLMTool", package: "swift-llm-client"),
            ]
        ),
        .testTarget(
            name: "AgentSkillsToolTests",
            dependencies: [
                "AgentSkillsTool",
                .product(name: "PersistenceTesting", package: "swift-persistence"),
            ]
        ),
    ]
)
