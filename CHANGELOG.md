# Changelog

## [Unreleased]

## [0.4.0] - 2026-08-11

### Fixed

- **BREAKING** — `SkillWriter` joined an unvalidated name to the skills root, so a name could name
  a path outside it. Reproduced, and worse than a read: `delete(name: "../../Documents")` removed a
  tree outside the root, `delete(name: "")` resolved to the root itself and wiped every skill, and
  `update(originalName: "../../Documents")` **moved an outside directory into the skills root**.
  All three now route through one containment gate that requires the resolved parent to be the
  root, and refuse with `SkillWriteError.nameEscapesRoot`.

  Containment here is structural — exactly one component under the root — not symlink-resolving,
  because this type is generic over a filesystem abstraction with no symlink capability. A symlink
  planted inside the skills root is still followed on the disk-backed path.


## [0.3.0] - 2026-08-11

### Changed

- Raised the swift-llm-client pin to 4.0.0 and the swift-structured-data pin to 3.0.0. Neither
  changes this package's own API: llm-client 4.0.0 alters protocol *requirement* signatures, which
  affects types that conform to them, not code that calls them.


## [0.2.0] - 2026-07-19

See [GitHub Releases](../../releases) for changes up to and including this version.
