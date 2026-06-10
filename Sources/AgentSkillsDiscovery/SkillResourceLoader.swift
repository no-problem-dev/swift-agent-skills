import Foundation
import PersistenceCore

/// Discovers a skill's bundled `scripts/`/`references/`/`assets/` files.
///
/// Mirrors OpenHands `discover_skill_resources`: enumerates files (recursively,
/// returning relative paths) under each standard directory. Files are listed,
/// never read — the model loads them on demand.
enum SkillResourceLoader {

    static func discover(in skillDirectory: URL, fileSystem: some FileSystemReading) async -> SkillResources? {
        var scripts: [String] = []
        var references: [String] = []
        var assets: [String] = []

        for name in SkillResources.directoryNames {
            let dir = skillDirectory.appendingPathComponent(name)
            guard await fileSystem.isDirectory(dir) else { continue }
            let files = await relativeFiles(under: dir, base: dir, fileSystem: fileSystem)
            switch name {
            case "scripts": scripts = files
            case "references": references = files
            case "assets": assets = files
            default: break
            }
        }

        let resources = SkillResources(
            root: skillDirectory.standardizedFileURL,
            scripts: scripts, references: references, assets: assets
        )
        return resources.hasResources ? resources : nil
    }

    private static func relativeFiles(
        under directory: URL,
        base: URL,
        fileSystem: some FileSystemReading
    ) async -> [String] {
        guard let entries = try? await fileSystem.contentsOfDirectory(directory) else { return [] }
        var result: [String] = []
        for entry in entries.sorted(by: { $0.path < $1.path }) {
            if await fileSystem.isDirectory(entry) {
                result += await relativeFiles(under: entry, base: base, fileSystem: fileSystem)
            } else {
                result.append(relativePath(of: entry, from: base))
            }
        }
        return result
    }

    private static func relativePath(of url: URL, from base: URL) -> String {
        let baseComponents = base.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.count > baseComponents.count,
              Array(urlComponents.prefix(baseComponents.count)) == baseComponents
        else { return url.lastPathComponent }
        return urlComponents.dropFirst(baseComponents.count).joined(separator: "/")
    }
}
