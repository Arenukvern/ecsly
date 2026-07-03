# Changelog

## Unreleased

## [0.0.1-dev.12](https://github.com/Arenukvern/ecsly/compare/ecsly-v0.0.1-dev.11...ecsly-v0.0.1-dev.12) (2026-07-03)


### Documentation

* update DESIGN_FAQ and README to clarify `flutterFrame` terminology and its implications for ECS schedules ([0abf728](https://github.com/Arenukvern/ecsly/commit/0abf728c8a14a47ff286c69c9c154258740ce15b))

## [0.0.1-dev.11](https://github.com/Arenukvern/ecsly/compare/ecsly-v0.0.1-dev.10...ecsly-v0.0.1-dev.11) (2026-07-02)


### Documentation

* clarify ecsly resource boundaries and release automation ([371dfec](https://github.com/Arenukvern/ecsly/commit/371dfec85e3dc8ff59fca0ca2b6edde4de2b1d8f))
* **ecsly:** clarify resource system boundaries ([e38f11e](https://github.com/Arenukvern/ecsly/commit/e38f11ecd30e309a55ad60c06e261cef61c99cf4))

## 0.0.1-dev.10 - 2026-07-02

- Moved the public-canonical source for the core package to
  `core_packages/ecsly` in the public repo and restored public repository,
  issue tracker, and license metadata.
- Kept core revision state scoped to structural/query topology only. Removed
  host-facing component/resource revision maps and mutation markers; semantic
  UI/app invalidation now belongs to `ecsly_app` / `ecsly_flutter`.
- Coalesced `structuralRevision` / `queryRevision` into topology epochs at
  command-flush boundaries instead of per-entity structural operation counts.
- Added prepared query helpers (`prepareQuery*`) so callers can cache query
  shapes while `ecsly` keeps membership invalidation tied to structural flushes.
- Kept nullable component lookup scoped to direct runtime `Entity` reads and
  removed the unreleased predicate/domain-id lookup helpers from core.
- Clarified that persistent app/domain ids belong in components or plugin
  infrastructure, not `World` identity.

## 0.0.1-dev.9

- Readme cleanup

## 0.0.1-dev.8

- Restored the softer raster logo as the canonical README logo.
- Replaced the hand-redrawn SVG logo with an SVG compatibility copy that embeds
  the canonical PNG, avoiding a second weaker visual identity.
- Bumped package version metadata to `0.0.1-dev.8`.

## 0.0.1-dev.7

- Added pub.dev topics and explicit platform metadata for Android, iOS, Linux,
  macOS, web, and Windows.
- Added newcomer examples for extension components, commands/resources, and
  SIMD-friendly typed columns.
- Expanded README and DX FAQ with compact explanations for extension facades,
  deferred commands, resources, and SIMD storage.
- Expanded DESIGN FAQ rationale for SIMD stride-4 storage, deferred commands,
  and resources.
- Removed non-public repository and issue tracker URLs from package metadata until
  public links exist.
- Switched the root license file to standard MIT text so pub.dev can recognise
  the OSI-approved license.
- Added a canonical `example/main.dart` entry point and example index for
  pub.dev example detection.
- Added dartdoc for the public `Archetype` constructor, identity, signature,
  entity list, and entity count.
- Clarified package positioning as a pure-Dart ECS core usable from Flutter,
  Jaspr, CLI tools, tests, and other Dart hosts.
- Added a compact README walkthrough for SIMD-friendly extension components and
  packed `Float32x4` column updates.
- Clarified that resources may be immutable snapshots, mutable runtime state,
  or a small mix of both when they remain data-only.
- Added brand/reference assets: a soft typography-based SVG logo, usage card,
  API story card, and performance/storage card for README and pub.dev.
- Bumped package version metadata to `0.0.1-dev.7`.

## 0.0.1-dev.6

- Recorded richer benchmark machine metadata, including Mac model, CPU, and RAM.
- Added game-perspective benchmark metrics for frame p95/p99,
  render-packet-like extraction, packet bytes, and spawn/despawn churn.
- Updated benchmark docs to map metrics back to prototype perf concerns.
- Bumped package version metadata to `0.0.1-dev.6`.

## 0.0.1-dev.5

- Added a benchmark results ADR and generated-report workflow.
- Expanded `benchmark/run.dart` with JSON, Markdown, single-pass report files,
  and limit-scan modes for stronger benchmark evidence.
- Added generated benchmark result artifacts under `benchmark/results/`.
- Added README/DX FAQ benchmark commands and report-reading guidance.
- Bumped package version metadata to `0.0.1-dev.5`.

## 0.0.1-dev.4

- Removed the remaining internal `ecs.dart` barrel path from the published
  archive by renaming it to `src/ecsly.dart`.
- Updated the public `ecsly.dart` entrypoint to export `src/ecsly.dart`.
- Bumped package version metadata to `0.0.1-dev.4`.

## 0.0.1-dev.3

- Fixed license/attribution naming language to consistently use `ecsly`.
- Removed the legacy `package:ecsly/ecs.dart` public entrypoint.
- Expanded README with concrete startup + usage guidance from `DX_FAQ.md` and selected `DESIGN_FAQ.md` expectations.
- Added two tiny runnable examples:
  - `example/basic_world.dart`
  - `example/scheduled_run.dart`
- Updated examples to avoid duplicating external movement components and
  keep custom extension/object components intentional in the scheduled example.
- Moved quickstart/example rationale into `DX_FAQ.md` and `DESIGN_FAQ.md`,
  keeping README concise for pub.dev.
- Bumped package version metadata to `0.0.1-dev.3`.

## 0.0.1-dev.2

- Package documentation metadata now points to autogenerated pub.dev documentation.
- Updated package readme publish links away from non-public repository paths.
- Adjusted maintainer workflow notes after docs/publication surface cleanup.

## 0.0.1-dev.1

- Initial super-experimental early prerelease release.
- API is evolving quickly and may change without semver guarantees until
  stable.
- Public APIs and diagnostics are provided on a best-effort basis.
- Acknowledgement: `ecsly` builds on foundational ideas inspired by the open
  ECS ecosystem, including [Bevy](https://bevyengine.org/) and
  [EnTT](https://github.com/skypjack/entt), and many other developers who
  advanced data-oriented architecture in game and simulation tooling.
