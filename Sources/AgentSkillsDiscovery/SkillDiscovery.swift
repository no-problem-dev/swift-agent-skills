import Foundation
import AgentSkills
import PersistenceCore

/// スキルをあるソースから探索して寛容に読み込むプロトコル。
public protocol SkillDiscovering: Sendable {
    /// スキルを探索し、ロードした結果と診断（警告・エラー）を返す。
    ///
    /// 実装は寛容（warn-and-load）— 厳格バリデーションに失敗しても本体と description が揃っていれば読み込み、
    /// 問題は ``DiscoveredSkills/diagnostics`` に記録する。
    func discover() async -> DiscoveredSkills
}

/// ファイルシステムベースの探索設定。
public struct SkillDiscoveryConfig: Sendable {
    /// プロジェクトツリーの起点（親ディレクトリウォークの開始点）。
    public var projectRoot: URL?
    /// 親ウォークの終点（例: git/worktree ルート）。ここを含む上位は探索しない。
    public var worktreeStop: URL?
    /// ユーザーレベルスキルのホームディレクトリ。
    public var homeDirectory: URL?
    /// `.agents/skills/` を探索するか（クロスクライアント標準の場所）。
    public var scanAgentsDir: Bool
    /// `.claude/skills/` を探索するか（既存スキルとの実用的な互換性）。
    public var scanClaudeDir: Bool
    /// 追加で明示的に探索するスキルルート。
    public var extraRoots: [URL]
    /// ルート内の最大ディレクトリ探索深度。
    public var maxDepth: Int
    /// ルートあたりの最大訪問ディレクトリ数（暴走ガード）。
    public var maxEntries: Int
    /// プロジェクトレベルルートのトラストゲート。信頼されていないルートはスキップする。
    public var isTrusted: @Sendable (URL) -> Bool

    public init(
        projectRoot: URL? = nil,
        worktreeStop: URL? = nil,
        homeDirectory: URL? = nil,
        scanAgentsDir: Bool = true,
        scanClaudeDir: Bool = true,
        extraRoots: [URL] = [],
        maxDepth: Int = 6,
        maxEntries: Int = 2000,
        isTrusted: @escaping @Sendable (URL) -> Bool = { _ in true }
    ) {
        self.projectRoot = projectRoot
        self.worktreeStop = worktreeStop
        self.homeDirectory = homeDirectory
        self.scanAgentsDir = scanAgentsDir
        self.scanClaudeDir = scanClaudeDir
        self.extraRoots = extraRoots
        self.maxDepth = maxDepth
        self.maxEntries = maxEntries
        self.isTrusted = isTrusted
    }
}

/// スキルが発見されたスコープ。衝突時の優先度を決定する（explicit > project > user）。
public enum SkillScope: Int, Sendable, Comparable {
    case user = 0
    case project = 1
    case explicit = 2
    public static func < (lhs: SkillScope, rhs: SkillScope) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// インジェクトされた ``FileSystemReading`` を介してファイルシステムから寛容にスキルを探索する実装。
public struct FileSystemSkillDiscovery<FS: FileSystemReading>: SkillDiscovering {
    private let config: SkillDiscoveryConfig
    private let fileSystem: FS

    public init(config: SkillDiscoveryConfig, fileSystem: FS) {
        self.config = config
        self.fileSystem = fileSystem
    }

    public func discover() async -> DiscoveredSkills {
        var loaded: [(scope: SkillScope, skill: LoadedSkill)] = []
        var diagnostics: [SkillDiagnostic] = []

        for (scope, root) in await scanRoots() {
            if scope == .project && !config.isTrusted(root) { continue }
            for manifest in await findManifests(in: root) {
                let (skill, diags) = await loadSkill(manifest: manifest)
                diagnostics += diags
                if let skill { loaded.append((scope, skill)) }
            }
        }

        // Merge by name; higher scope wins, with a collision warning.
        var byName: [String: (scope: SkillScope, skill: LoadedSkill)] = [:]
        for entry in loaded {
            if let existing = byName[entry.skill.name] {
                let (winner, loser) = entry.scope >= existing.scope ? (entry, existing) : (existing, entry)
                byName[entry.skill.name] = winner
                diagnostics.append(SkillDiagnostic(
                    .warning,
                    location: loser.skill.location.directory?.path ?? loser.skill.name,
                    message: "Duplicate skill name '\(entry.skill.name)' — shadowed by \(winner.scope)."
                ))
            } else {
                byName[entry.skill.name] = entry
            }
        }

        let skills = byName.values.map(\.skill).sorted { $0.name < $1.name }
        return DiscoveredSkills(skills: skills, diagnostics: diagnostics)
    }

    // MARK: - Roots

    private func scanRoots() async -> [(SkillScope, URL)] {
        var roots: [(SkillScope, URL)] = []
        let subdirs = skillSubdirNames()

        if let home = config.homeDirectory {
            for sub in subdirs {
                let root = home.appendingPathComponent(sub)
                if await fileSystem.isDirectory(root) { roots.append((.user, root)) }
            }
        }

        for dir in projectWalk() {
            for sub in subdirs {
                let root = dir.appendingPathComponent(sub)
                if await fileSystem.isDirectory(root) { roots.append((.project, root)) }
            }
        }

        for root in config.extraRoots where await fileSystem.isDirectory(root) {
            roots.append((.explicit, root))
        }
        return roots
    }

    private func skillSubdirNames() -> [String] {
        var names: [String] = []
        if config.scanAgentsDir { names.append(".agents/skills") }
        if config.scanClaudeDir { names.append(".claude/skills") }
        return names
    }

    /// `projectRoot` から `worktreeStop`（含む）までのディレクトリ一覧。
    private func projectWalk() -> [URL] {
        guard let start = config.projectRoot?.standardizedFileURL else { return [] }
        var dirs: [URL] = []
        var current = start
        let stop = config.worktreeStop?.standardizedFileURL
        while true {
            dirs.append(current)
            if current.path == stop?.path { break }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }  // reached filesystem root
            if stop == nil && current.path == start.path { break }  // no stop → just the start dir
            current = parent
        }
        return dirs
    }

    // MARK: - Scanning a root for SKILL.md

    private func findManifests(in root: URL) async -> [URL] {
        var manifests: [URL] = []
        var visited = 0
        var queue: [(URL, Int)] = [(root, 0)]

        while !queue.isEmpty {
            let (dir, depth) = queue.removeFirst()
            visited += 1
            if visited > config.maxEntries { break }

            guard let entries = try? await fileSystem.contentsOfDirectory(dir) else { continue }
            if let manifest = await SkillFrontmatter.findSkillMD(in: dir, fileSystem: fileSystem) {
                manifests.append(manifest)
                continue  // a skill dir; don't descend into its resource subdirs
            }
            if depth >= config.maxDepth { continue }
            for entry in entries where await shouldDescend(entry) {
                queue.append((entry, depth + 1))
            }
        }
        return manifests.sorted { $0.path < $1.path }
    }

    private func shouldDescend(_ url: URL) async -> Bool {
        guard await fileSystem.isDirectory(url) else { return false }
        let name = url.lastPathComponent
        return name != ".git" && name != "node_modules"
    }

    // MARK: - Lenient load

    private func loadSkill(manifest: URL) async -> (LoadedSkill?, [SkillDiagnostic]) {
        let skillDir = manifest.deletingLastPathComponent()
        let location = skillDir.path

        let content: String
        do {
            content = try await fileSystem.readString(manifest)
        } catch {
            return (nil, [SkillDiagnostic(.error, location: location, message: "Cannot read SKILL.md: \(error)")])
        }

        let frontmatter: StructuredFrontmatter
        do {
            let (parsed, body) = try SkillFrontmatter.parseFrontmatter(content)
            frontmatter = StructuredFrontmatter(object: parsed, body: body)
        } catch {
            return (nil, [SkillDiagnostic(.error, location: location, message: "Unparseable SKILL.md: \(error)")])
        }

        var diagnostics: [SkillDiagnostic] = []
        let dirName = skillDir.lastPathComponent

        // Description is essential for disclosure → skip if missing.
        guard let description = frontmatter.object["description"]?.string, !description.trimmed.isEmpty else {
            return (nil, [SkillDiagnostic(.error, location: location, message: "Skill is missing a description; skipped.")])
        }
        // Name: fall back to the directory name when absent.
        let name = frontmatter.object["name"]?.string?.trimmed.nonEmpty ?? dirName

        // Strict issues become warnings (warn-and-load).
        for issue in SkillValidator.validate(frontmatter: frontmatter.object, directoryName: dirName) {
            // Don't re-warn the description (already required above) — keep name/field issues.
            if issue.contains("description") { continue }
            diagnostics.append(SkillDiagnostic(.warning, location: location, message: issue))
        }

        let properties = SkillProperties(
            name: name,
            description: description.trimmed,
            license: frontmatter.object["license"]?.string,
            compatibility: frontmatter.object["compatibility"]?.string,
            allowedTools: frontmatter.object["allowed-tools"]?.string,
            metadata: SkillProperties.stringifiedMetadata(frontmatter.object["metadata"])
        )
        let resources = await SkillResourceLoader.discover(in: skillDir, fileSystem: fileSystem)

        let skill = LoadedSkill(
            name: name,
            description: description.trimmed,
            body: frontmatter.body,
            location: .file(manifest),
            properties: properties,
            resources: resources
        )
        return (skill, diagnostics)
    }
}

import StructuredDataCore

/// `loadSkill` がパース済みマッピングと本体を一緒に保持するための内部ホルダー。
private struct StructuredFrontmatter {
    let object: OrderedObject
    let body: String
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
